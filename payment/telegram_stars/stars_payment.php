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
