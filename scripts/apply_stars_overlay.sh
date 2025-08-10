#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "[+] Applying Telegram Stars overlay in $ROOT"

mkdir -p payment/telegram_stars migrations scripts

# 1) فایل پرداخت Stars
cat > payment/telegram_stars/stars_payment.php <<'PHP'
<?php
function tg_api($method, $data) {
    $url = "https://api.telegram.org/bot".TG_BOT_TOKEN."/".$method;
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_POSTFIELDS => json_encode($data, JSON_UNESCAPED_UNICODE),
        CURLOPT_TIMEOUT => 15,
    ]);
    $res = curl_exec($ch);
    if ($res === false) { error_log("tg_api error: ".curl_error($ch)); return false; }
    $data = json_decode($res, true);
    if (!$data || !isset($data['ok']) || !$data['ok']) { error_log("tg_api not ok: ".$res); }
    return $data;
}
function stars_send_invoice($chat_id, $orderId, $title, $desc, $starsAmount, $isSubscription=false) {
    $payload = "stars_" . $orderId . "_" . bin2hex(random_bytes(6));
    $body = [
        'chat_id' => $chat_id,
        'title' => $title,
        'description' => $desc,
        'payload' => $payload,
        'currency' => 'XTR',
        'prices' => [['label' => $title, 'amount' => (int)$starsAmount]],
    ];
    if ($isSubscription) { $body['subscription_period'] = 2592000; }
    $resp = tg_api('sendInvoice', $body);
    if (function_exists('db')) {
        try {
            $pdo = db();
            $stmt = $pdo->prepare("INSERT INTO payments (method, currency, tg_payload, status, created_at) VALUES ('telegram_stars','XTR',?, 'pending', NOW())");
            $stmt->execute([$payload]);
        } catch (Throwable $e) { error_log("stars persist error: ".$e->getMessage()); }
    }
    return $resp;
}
function stars_handle_update($update) {
    if (isset($update['pre_checkout_query'])) {
        tg_api('answerPreCheckoutQuery', ['pre_checkout_query_id' => $update['pre_checkout_query']['id'], 'ok' => true]);
        return true;
    }
    if (isset($update['message']['successful_payment'])) {
        $sp = $update['message']['successful_payment'];
        $payload  = $sp['invoice_payload'];
        $amount   = (int)$sp['total_amount'];
        $chargeId = $sp['telegram_payment_charge_id'];
        $chatId   = $update['message']['chat']['id'];
        $orderId = null;
        if (preg_match('/^stars_(\\d+)_/',$payload,$m)) { $orderId = (int)$m[1]; }
        if (function_exists('db')) {
            try {
                $pdo = db();
                $stmt = $pdo->prepare("SELECT id FROM payments WHERE tg_payload=? LIMIT 1");
                $stmt->execute([$payload]);
                $row = $stmt->fetch(PDO::FETCH_ASSOC);
                if ($row) {
                    $pid = (int)$row['id'];
                    $pdo->prepare("UPDATE payments SET status='paid', stars_total=?, tg_charge_id=?, paid_at=NOW() WHERE id=?")
                        ->execute([$amount, $chargeId, $pid]);
                }
            } catch (Throwable $e) { error_log("stars update error: ".$e->getMessage()); }
        }
        if (function_exists('fulfillOrder') && $orderId) { fulfillOrder($orderId); }
        tg_api('sendMessage', ['chat_id' => $chatId, 'text' => "پرداخت با موفقیت انجام شد ✅\nAmount: {$amount} XTR\nCharge: {$chargeId}"]);
        return true;
    }
    return false;
}
PHP

# 2) README کوتاه
cat > payment/telegram_stars/README.md <<'MD'
# Telegram Stars (XTR)
- sendInvoice با currency = XTR
- بدون provider_token
- هوک: stars_handle_update($update) در وبهوک اصلی
MD

# 3) مایگریشن
cat > migrations/2025_08_add_telegram_stars.sql <<'SQL'
ALTER TABLE payments 
  ADD COLUMN method ENUM('nowpayments','card2card','telegram_stars') NOT NULL DEFAULT 'telegram_stars',
  ADD COLUMN currency VARCHAR(8) DEFAULT 'XTR',
  ADD COLUMN stars_total BIGINT DEFAULT NULL,
  ADD COLUMN tg_payload VARCHAR(128) DEFAULT NULL,
  ADD COLUMN tg_charge_id VARCHAR(128) DEFAULT NULL,
  ADD COLUMN paid_at DATETIME NULL;
SQL

# 4) پچ index.php و admin.php
patch_php() {
  local file="$1"; [[ -f "$file" ]] || return 0
  if ! grep -q "payment/telegram_stars/stars_payment.php" "$file"; then
    sed -i '0,/<\?php/s//<?php\
require_once __DIR__ \x27\/payment\/telegram_stars\/stars_payment.php\x27;/' "$file"
  fi
  if grep -q "\$update = json_decode(file_get_contents('php:\/\/input'), true);" "$file" && \
     ! grep -q "stars_handle_update" "$file"; then
    sed -i "s|\$update = json_decode(file_get_contents('php://input'), true);|\$update = json_decode(file_get_contents('php://input'), true);\nif (is_array(\$update)) { stars_handle_update(\$update); }|g" "$file"
  fi
  if ! grep -q "action=payStars" "$file"; then
cat >> "$file" <<'ROUTE'

/** Minimal Stars route */
if (isset($_GET['action']) && $_GET['action']==='payStars') {
    $chat_id = isset($_GET['chat_id']) ? (int)$_GET['chat_id'] : 0;
    $orderId = isset($_GET['order_id']) ? (int)$_GET['order_id'] : 0;
    $title   = isset($_GET['title']) ? $_GET['title'] : 'Purchase';
    $desc    = isset($_GET['desc']) ? $_GET['desc'] : 'Service';
    $amount  = isset($_GET['amount']) ? (int)$_GET['amount'] : 0;
    if ($chat_id && $orderId && $amount>0) {
        stars_send_invoice($chat_id, $orderId, $title, $desc, $amount, false);
        echo "OK";
    } else {
        http_response_code(400);
        echo "Missing parameters";
    }
    exit;
}
ROUTE
  fi
}
patch_php "index.php"
patch_php "admin.php"

# 5) فقط این درگاه‌ها بمانند
cat > scripts/cleanup_gateways.sh <<'CLEAN'
#!/usr/bin/env bash
set -euo pipefail
PAYDIR="payment"
if [[ -d "$PAYDIR" ]]; then
  for d in "$PAYDIR"/*; do
    [[ -d "$d" ]] || continue
    bn="$(basename "$d")"
    case "$bn" in
      nowpayments|card2card|telegram_stars) echo "keep: $bn";;
      *) echo "removing: $bn"; rm -rf "$d";;
    esac
  done
else
  echo "payment directory not found."
fi
echo "Done."
CLEAN
chmod +x scripts/cleanup_gateways.sh

# 6) لینک‌های ریپو را به فورک خودت تغییر بده
cat > scripts/retarget_links.sh <<'RETARGET'
#!/usr/bin/env bash
set -euo pipefail
find . -type f \( -name "*.md" -o -name "*.sh" -o -name "*.php" -o -name "*.txt" \) -print0 | \
xargs -0 sed -i 's#raw.githubusercontent.com/LiamAghamohammadi/MarzBot#raw.githubusercontent.com/LiamAghamohammadi/MarzBot#g'
find . -type f \( -name "*.md" -o -name "*.sh" -o -name "*.php" -o -name "*.txt" \) -print0 | \
xargs -0 sed -i 's#github.com/LiamAghamohammadi/MarzBot#github.com/LiamAghamohammadi/MarzBot#g'
echo "All repo links retargeted to LiamAghamohammadi/MarzBot"
RETARGET
chmod +x scripts/retarget_links.sh

# 7) اگر توکن بات نبود، اضافه کن
if [[ -f "config.php" ]] && ! grep -q "TG_BOT_TOKEN" config.php; then
  sed -i '0,/<\?php/s//<?php\
if (!defined(\x27TG_BOT_TOKEN\x27)) { define(\x27TG_BOT_TOKEN\x27, getenv(\x27TG_BOT_TOKEN\x27) ?: \x27PASTE_YOUR_BOT_TOKEN\x27); }/' config.php
fi

echo "[+] Overlay applied."
