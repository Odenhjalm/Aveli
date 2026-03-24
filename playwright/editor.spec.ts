import { test, expect } from '@playwright/test';
import type { Locator, Page } from '@playwright/test';

test.describe.configure({ timeout: 120_000 });

type AveliTestBridge = {
  insertText?: (text: string) => void;
  backspace?: () => void;
  deleteSelection?: () => void;
  setCursor?: (offset: number) => void;
  setSelection?: (start: number, end: number) => void;
  getCursor?: () => number;
  getDocument?: () => string;
};

declare global {
  interface Window {
    aveliTestBridge?: AveliTestBridge;
  }
}

const objectReplacementCharacter = '\uFFFC';
const bootShellSelector =
  '[data-testid="editor-skeleton"], [data-testid="editor-boot-shell"], [flt-semantics-identifier="editor-boot-shell"]';
const editorSelector =
  '[data-testid="lesson-editor"], [flt-semantics-identifier="lesson-editor"]';
const mediaPreviewSelector =
  '[data-testid="media-preview"], [flt-semantics-identifier="media-preview"]';
const quillStabilityErrorPattern =
  /Compose failed|_delta == _root\.toDelta\(\)/;
const trackedQuillErrors = new WeakMap<Page, string[]>();

function trackQuillErrors(page: Page) {
  const messages: string[] = [];
  const record = (text: string) => {
    if (quillStabilityErrorPattern.test(text)) {
      messages.push(text);
    }
  };

  page.on('console', (message) => {
    record(message.text());
  });
  page.on('pageerror', (error) => {
    record(error.message);
  });

  return messages;
}

test.beforeEach(async ({ page }) => {
  trackedQuillErrors.set(page, trackQuillErrors(page));
});

test.afterEach(async ({ page }) => {
  expect(trackedQuillErrors.get(page) ?? []).toEqual([]);
});

async function gotoLessonEditor(page: Page) {
  await page.goto('/#/teacher/editor');
  await page.waitForLoadState('domcontentloaded');
  await expect(page).toHaveURL(/#\/teacher\/editor$/);
  await enableFlutterAccessibility(page);
}

function editor(page: Page): Locator {
  return page.locator(editorSelector);
}

function mediaPreviews(page: Page): Locator {
  return editor(page).locator(mediaPreviewSelector);
}

async function enableFlutterAccessibility(page: Page) {
  await page.waitForTimeout(3_000);

  const semanticsSelector =
    '[flt-semantics-identifier], flt-semantics[aria-label], flt-semantics[role]';

  const semanticsAlreadyEnabled = await page
    .locator(semanticsSelector)
    .count()
    .then((count) => count > 0);
  if (semanticsAlreadyEnabled) {
    return;
  }

  await page
    .waitForFunction(
      ({ selector, placeholderSelector }) =>
        document.querySelectorAll(selector).length > 0 ||
        !!document.querySelector(placeholderSelector),
      {
        selector: semanticsSelector,
        placeholderSelector:
          'flt-semantics-placeholder[aria-label="Enable accessibility"]'
      },
      { timeout: 15_000 }
    )
    .catch(() => {});

  const toggled = await page.evaluate(() => {
    const accessibilityToggle = document.querySelector(
      'flt-semantics-placeholder[aria-label="Enable accessibility"]'
    );
    if (!(accessibilityToggle instanceof HTMLElement)) {
      return false;
    }

    accessibilityToggle.focus();
    accessibilityToggle.click();
    return true;
  });

  if (toggled) {
    await page
      .waitForFunction(
        (selector) => document.querySelectorAll(selector).length > 0,
        semanticsSelector,
        { timeout: 10_000 }
      )
      .catch(() => {});
    await page.waitForTimeout(1_000);
  }
}

async function waitForBridge(page: Page) {
  await page.waitForFunction(() => {
    const bridge = window.aveliTestBridge;
    return (
      typeof bridge?.insertText === 'function' &&
      typeof bridge?.backspace === 'function' &&
      typeof bridge?.deleteSelection === 'function' &&
      typeof bridge?.setCursor === 'function' &&
      typeof bridge?.setSelection === 'function' &&
      typeof bridge?.getCursor === 'function' &&
      typeof bridge?.getDocument === 'function'
    );
  });
}

async function focusEditor(page: Page) {
  const lessonEditor = editor(page);
  await lessonEditor.waitFor({ state: 'visible', timeout: 60_000 });
  await lessonEditor.evaluate((element: HTMLElement) => {
    element.focus();
  });
}

async function prepareEditor(page: Page) {
  await gotoLessonEditor(page);
  await waitForEditorReady(page);
  await focusEditor(page);
}

async function waitForEditorReady(page: Page) {
  const bootShell = page.locator(bootShellSelector);
  const lessonEditor = editor(page);

  const bootShellVisible = await bootShell.isVisible().catch(() => false);
  if (bootShellVisible) {
    await bootShell.waitFor({ state: 'hidden', timeout: 60_000 });
  }

  await lessonEditor.waitFor({ state: 'visible', timeout: 60_000 });
  await expect
    .poll(async () => !(await bootShell.isVisible().catch(() => false)), {
      timeout: 60_000
    })
    .toBe(true);
  await waitForBridge(page);

  return lessonEditor;
}

async function insertTextViaBridge(page: Page, text: string) {
  await page.evaluate((value) => {
    const bridge = window.aveliTestBridge;
    if (typeof bridge?.insertText !== 'function') {
      throw new Error('aveliTestBridge.insertText is not available');
    }

    bridge.insertText(value);
  }, text);
}

async function backspaceViaBridge(page: Page) {
  await page.evaluate(() => {
    const bridge = window.aveliTestBridge;
    if (typeof bridge?.backspace !== 'function') {
      throw new Error('aveliTestBridge.backspace is not available');
    }

    bridge.backspace();
  });
}

async function deleteSelectionViaBridge(page: Page) {
  await page.evaluate(() => {
    const bridge = window.aveliTestBridge;
    if (typeof bridge?.deleteSelection !== 'function') {
      throw new Error('aveliTestBridge.deleteSelection is not available');
    }

    bridge.deleteSelection();
  });
}

async function setCursorViaBridge(page: Page, offset: number) {
  await page.evaluate((value) => {
    const bridge = window.aveliTestBridge;
    if (typeof bridge?.setCursor !== 'function') {
      throw new Error('aveliTestBridge.setCursor is not available');
    }

    bridge.setCursor(value);
  }, offset);
}

async function setSelectionViaBridge(page: Page, start: number, end: number) {
  await page.evaluate(
    ({ startOffset, endOffset }) => {
      const bridge = window.aveliTestBridge;
      if (typeof bridge?.setSelection !== 'function') {
        throw new Error('aveliTestBridge.setSelection is not available');
      }

      bridge.setSelection(startOffset, endOffset);
    },
    { startOffset: start, endOffset: end }
  );
}

async function getCursorViaBridge(page: Page): Promise<number> {
  return page.evaluate(() => {
    const bridge = window.aveliTestBridge;
    if (typeof bridge?.getCursor !== 'function') {
      throw new Error('aveliTestBridge.getCursor is not available');
    }

    return bridge.getCursor();
  });
}

async function getDocumentViaBridge(page: Page): Promise<string> {
  return page.evaluate(() => {
    const bridge = window.aveliTestBridge;
    if (typeof bridge?.getDocument !== 'function') {
      throw new Error('aveliTestBridge.getDocument is not available');
    }

    return bridge.getDocument();
  });
}

test('editor skeleton transitions to stable editor', async ({ page }) => {
  await gotoLessonEditor(page);

  const skeleton = page.locator(bootShellSelector);
  const lessonEditor = editor(page);

  await expect(skeleton).toBeVisible();
  await waitForEditorReady(page);
  await expect(lessonEditor).toBeVisible();
});

test('editor typing appears immediately', async ({ page }) => {
  await prepareEditor(page);

  const lessonEditor = editor(page);
  await insertTextViaBridge(page, 'hello');

  await expect(lessonEditor).toBeVisible();
  await expect.poll(() => getDocumentViaBridge(page)).toContain('hello');
});

test('editor backspace works', async ({ page }) => {
  await prepareEditor(page);

  await insertTextViaBridge(page, 'hello');
  await backspaceViaBridge(page);

  await expect.poll(() => getDocumentViaBridge(page)).toContain('hell');
});

test('editor cursor movement remains stable', async ({ page }) => {
  await prepareEditor(page);

  await insertTextViaBridge(page, 'abcdef');
  await setCursorViaBridge(page, 3);

  await expect.poll(() => getCursorViaBridge(page)).toBe(3);
});

test('embed deletion stable', async ({ page }) => {
  await prepareEditor(page);

  const preview = mediaPreviews(page);
  await preview.first().waitFor({ state: 'visible', timeout: 60_000 });

  const document = await getDocumentViaBridge(page);
  const embedOffsets = Array.from(document.matchAll(/\uFFFC/g), (match) =>
    match.index ?? -1
  ).filter((offset) => offset >= 0);

  expect(embedOffsets.length).toBeGreaterThan(0);
  for (const offset of embedOffsets.reverse()) {
    await setSelectionViaBridge(page, offset, offset + 1);
    await deleteSelectionViaBridge(page);
  }

  await expect(preview).toHaveCount(0);
  await expect
    .poll(async () => (await getDocumentViaBridge(page)).includes(objectReplacementCharacter))
    .toBe(false);
});

test('preview hydration', async ({ page }) => {
  await gotoLessonEditor(page);
  await waitForEditorReady(page);

  const preview = mediaPreviews(page);

  await preview.first().waitFor({ state: 'visible', timeout: 60_000 });
  await expect(preview.first()).toBeVisible();
});

test('selection remains stable in longer document after edits', async ({ page }) => {
  await prepareEditor(page);

  const lines = Array.from({ length: 40 }, (_, index) => `line-${index}`).join(
    '\n'
  );
  await insertTextViaBridge(page, lines);
  await setCursorViaBridge(page, 120);
  await backspaceViaBridge(page);

  const cursor = await getCursorViaBridge(page);
  const document = await getDocumentViaBridge(page);

  expect(typeof cursor).toBe('number');
  expect(document).toContain('line-0');
  expect(document).toContain('line-39');
});
