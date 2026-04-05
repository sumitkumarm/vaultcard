const sampleBalanceHtml = '''
<html>
  <body>
    <div class="balance-amount">\$42.15</div>
    <table class="transactions">
      <tbody>
        <tr>
          <td class="date">04/01/2026</td>
          <td class="description">Coffee Shop</td>
          <td class="amount">-\$5.25</td>
        </tr>
        <tr>
          <td class="date">03/31/2026</td>
          <td class="description">Initial Load</td>
          <td class="amount">\$47.40</td>
        </tr>
      </tbody>
    </table>
  </body>
</html>
''';

const sampleBotProtectionHtml = '''
<html lang="en">
  <head>
    <title>giftcardmall.com</title>
  </head>
  <body style="margin:0">
    <p id="cmsg">Please enable JS and disable any ad blocker</p>
    <script data-cfasync="false">
      var dd = {
        'host': 'geo.captcha-delivery.com',
        'cookie': 'datadome=abc123'
      };
    </script>
  </body>
</html>
''';
