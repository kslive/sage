import { test } from "node:test";
import assert from "node:assert/strict";
import { docSendDelay } from "../src/core.js";

// docSendDelay: дебаунс 250мс, но отправка не позже maxWait (1000мс) от первого несохранённого ввода.

test("нет несохранённого ввода → полный дебаунс", () => {
  assert.equal(docSendDelay(10_000, 0), 250);
});

test("свежий pending → дебаунс не режется", () => {
  assert.equal(docSendDelay(10_000, 10_000), 250);
  assert.equal(docSendDelay(10_100, 10_000), 250);
});

test("pending старше 750мс → задержка ужимается до дедлайна", () => {
  assert.equal(docSendDelay(10_800, 10_000), 200);
  assert.equal(docSendDelay(10_900, 10_000), 100);
});

test("дедлайн достигнут/пройден → 0, не отрицательная", () => {
  assert.equal(docSendDelay(11_000, 10_000), 0);
  assert.equal(docSendDelay(12_345, 10_000), 0);
});

test("кастомные debounce/maxWait уважаются", () => {
  assert.equal(docSendDelay(1_000, 900, 100, 500), 100);
  assert.equal(docSendDelay(1_350, 900, 100, 500), 50);
});
