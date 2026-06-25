// Юнит-тест анти-фантомного-выделения: одиночный плоский клик не оставляет диапазон. Раннер: node --test.
import { test } from "node:test";
import assert from "node:assert/strict";
import { shouldCollapseClick } from "../src/core.js";

test("shouldCollapseClick: одиночный плоский клик при диапазоне → схлопнуть", () => {
  // button=0 (левый), detail=1 (одиночный), без сдвига, выделение НЕ пустое
  assert.equal(shouldCollapseClick(0, 1, 0, 0, false), true);
  assert.equal(shouldCollapseClick(0, 1, 2, -3, false), true);   // микродрожь ≤3px — всё ещё клик
});

test("shouldCollapseClick: НЕ трогаем когда уже курсор / drag / dbl / правый клик", () => {
  assert.equal(shouldCollapseClick(0, 1, 0, 0, true), false);    // выделение пустое (курсор) → нечего схлопывать
  assert.equal(shouldCollapseClick(0, 1, 10, 0, false), false);  // сдвиг по X >3 → настоящий drag-select
  assert.equal(shouldCollapseClick(0, 1, 0, 8, false), false);   // сдвиг по Y >3 → drag
  assert.equal(shouldCollapseClick(0, 2, 0, 0, false), false);   // double-click → слово, не трогаем
  assert.equal(shouldCollapseClick(0, 3, 0, 0, false), false);   // triple-click → строка
  assert.equal(shouldCollapseClick(2, 1, 0, 0, false), false);   // правый клик
});
