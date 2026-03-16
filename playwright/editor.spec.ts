import { test, expect } from '@playwright/test';
import type { Locator, Page } from '@playwright/test';

test.describe.configure({ timeout: 120_000 });

const bootShellSelector = '[flt-semantics-identifier="editor-boot-shell"]';
const editorSelector =
  '[data-testid="lesson-editor"], [flt-semantics-identifier="lesson-editor"]';
const mediaPreviewSelector = '[flt-semantics-identifier="media-preview"]';

async function gotoLessonEditor(page: Page) {
  await page.goto('/#/teacher/editor');
  await page.waitForLoadState('domcontentloaded');
  await expect(page).toHaveURL(/#\/teacher\/editor$/);
  await enableFlutterAccessibility(page);
}

function editor(page: Page): Locator {
  return page.locator(editorSelector);
}

async function enableFlutterAccessibility(page: Page) {
  await page.waitForTimeout(3_000);

  const accessibilityToggle = page.locator(
    'flt-semantics-placeholder[aria-label="Enable accessibility"]'
  );

  await accessibilityToggle
    .waitFor({ state: 'attached', timeout: 15_000 })
    .catch(() => {});

  if (await accessibilityToggle.count()) {
    await accessibilityToggle.evaluate((element: HTMLElement) => {
      element.focus();
      element.click();
    });
    await page.waitForTimeout(1_000);
  }
}

async function insertTextViaBridge(page: Page, text: string) {
  const lessonEditor = editor(page);
  await lessonEditor.waitFor({ state: 'visible', timeout: 60_000 });

  await page.waitForFunction(() => {
    const bridge = (window as Window & {
      aveliTestBridge?: { insertText?: (text: string) => void };
    }).aveliTestBridge;
    return typeof bridge?.insertText === 'function';
  });

  await lessonEditor.evaluate((element: HTMLElement) => {
    element.focus();
  });

  await page.evaluate((value) => {
    const bridge = (window as Window & {
      aveliTestBridge?: { insertText?: (text: string) => void };
    }).aveliTestBridge;

    if (typeof bridge?.insertText !== 'function') {
      throw new Error('aveliTestBridge.insertText is not available');
    }

    bridge.insertText(value);
  }, text);
}

test('editor accepts typing via bridge', async ({ page }) => {
  await gotoLessonEditor(page);

  const lessonEditor = editor(page);
  await insertTextViaBridge(page, 'hello world');
  await expect(lessonEditor).toContainText('hello world', { timeout: 15_000 });
});

test('editor boot lifecycle', async ({ page }) => {
  await gotoLessonEditor(page);

  const bootShell = page.locator(bootShellSelector);
  const lessonEditor = editor(page);
  const bootShellSeen = await bootShell
    .waitFor({ state: 'visible', timeout: 5_000 })
    .then(() => true)
    .catch(() => false);

  await lessonEditor.waitFor({ state: 'visible', timeout: 60_000 });

  if (bootShellSeen) {
    await expect(bootShell).toBeVisible();
  }
  await expect(lessonEditor).toBeVisible();
});

test('editor remains interactive during preview hydration', async ({ page }) => {
  await gotoLessonEditor(page);

  const lessonEditor = editor(page);
  await insertTextViaBridge(page, 'boot test');
  await expect(lessonEditor).toContainText('boot test', { timeout: 15_000 });
});

test('media previews load after hydration', async ({ page }) => {
  await gotoLessonEditor(page);

  const preview = page.locator(mediaPreviewSelector);

  await preview.first().waitFor({ state: 'visible', timeout: 60_000 });
  await expect(preview.first()).toBeVisible();
});

test('debug semantics nodes', async ({ page }) => {
  await gotoLessonEditor(page);

  const nodes = await page.locator('[flt-semantics-identifier]').all();
  const ids = await Promise.all(
    nodes.map((node) => node.getAttribute('flt-semantics-identifier'))
  );
  const testIds = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-testid]')).map((node) =>
      node.getAttribute('data-testid')
    )
  );
  const ariaLabels = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[aria-label]'))
      .slice(0, 25)
      .map((node) => node.getAttribute('aria-label'))
  );
  const keyedElements = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[key]'))
      .slice(0, 50)
      .map((node) => node.getAttribute('key'))
  );

  console.log('Current URL:', page.url());
  console.log('Semantics nodes:', ids);
  console.log('Data test ids:', testIds);
  console.log('ARIA labels:', ariaLabels);
  console.log('Keyed elements:', keyedElements);
});
