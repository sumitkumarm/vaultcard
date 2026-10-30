// Run the actual injected parser with small DOM fixtures: node --test ios-native/tests/available-balance.test.cjs
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const { test } = require('node:test');
const assert = require('node:assert/strict');

const source = readFileSync(`${__dirname}/../VaultCard/VaultCardApp.swift`, 'utf8');
const parser = source.slice(source.indexOf('          let lastDOMBalance = null;'), source.indexOf('          const isCardResponse'))
  .replace(/\\\\/g, '\\'); // Decode Swift multiline string regex escapes.

test('UI refresh fixture includes the same source as real page captures', () => {
  assert.match(source, /"kind": "domBalance",\s*"source": "availableBalanceSummary",\s*"balance": arguments/);
});

function node(text, parentElement = null, { hidden = false, table = false } = {}) {
  return {
    textContent: text, parentElement,
    getClientRects: () => hidden ? [] : [{}],
    closest: () => table ? {} : null,
  };
}

function inspect(elements) {
  const messages = [];
  const context = {
    document: { querySelectorAll: () => elements },
    post: message => messages.push(message),
  };
  runInNewContext(`${parser}\nthis.inspectBalance = inspectBalance;`, context);
  context.inspectBalance();
  return { messages, context };
}

test('saves $23.56 summary, never $79.83 transaction or $200 initial balance', () => {
  const summary = node('Available Balance $23.56');
  const label = node('Available Balance', summary);
  const elements = [node('$79.83', null, { table: true }), node('Initial Balance $200.00'), summary, label];
  const { messages, context } = inspect(elements);
  assert.equal(messages.length, 1);
  assert.equal(messages[0].balance, 23.56);
  assert.equal(messages[0].source, 'availableBalanceSummary');
  context.inspectBalance();
  assert.equal(messages.length, 1, 'repeated inspection cannot overwrite the summary with another amount');
});

test('does not save a balance when only transaction and initial balances exist', () => {
  assert.equal(inspect([node('$79.83'), node('Initial Balance $200.00')]).messages.length, 0);
});

test('ignores hidden labels and labels inside transaction tables', () => {
  const container = node('Available Balance $79.83');
  for (const options of [{ hidden: true }, { table: true }]) {
    assert.equal(inspect([node('Available Balance', container, options)]).messages.length, 0);
  }
});

test('supports zero, thousands, and nested summary markup without requiring viewport visibility', () => {
  for (const [text, amount] of [['$0.00', 0], ['$1,234.56', 1234.56]]) {
    const container = node(`Available Balance\n ${text}`);
    const label = node(' Available\n Balance ', node('Available Balance', container));
    assert.equal(inspect([label]).messages[0].balance, amount);
    assert.equal(inspect([container]).messages[0].balance, amount);
  }
});

test('rejects ambiguous containers and negative amounts', () => {
  for (const text of ['Available Balance $23.56 Initial Balance $200.00', 'Available Balance -$23.56']) {
    assert.equal(inspect([node('Available Balance', node(text))]).messages.length, 0);
  }
});
