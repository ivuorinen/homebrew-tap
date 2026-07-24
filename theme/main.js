// Theme toggle: cycles auto -> light -> dark -> auto. Auto follows the OS.
(() => {
  const STORAGE_KEY = "theme";
  const ORDER = ["auto", "light", "dark"];
  const ICONS = { auto: "🌗", light: "☀️", dark: "🌙" };
  const LABELS = { auto: "Auto", light: "Light", dark: "Dark" };

  function getMode() {
    let mode = null;
    try {
      mode = localStorage.getItem(STORAGE_KEY);
    } catch {
      // Ignore storage failures
    }
    return ORDER.includes(mode) ? mode : "auto";
  }

  function setMode(mode) {
    try {
      localStorage.setItem(STORAGE_KEY, mode);
    } catch {
      // Ignore storage failures
    }
  }

  function resolve(mode) {
    if (mode !== "auto") return mode;
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  }

  function apply(mode) {
    const theme = resolve(mode);
    const root = document.documentElement;
    root.classList.toggle("dark", theme === "dark");
    root.classList.toggle("light", theme !== "dark");
    root.setAttribute("data-theme", theme);

    const toggle = document.querySelector(".theme-toggle");
    if (toggle) {
      const icon = toggle.querySelector(".theme-toggle-icon");
      const label = toggle.querySelector(".theme-toggle-label");
      if (icon) icon.textContent = ICONS[mode];
      if (label) label.textContent = LABELS[mode];
      toggle.setAttribute("aria-label", `Theme: ${LABELS[mode]}`);
    }
  }

  function cycleTheme() {
    const next = ORDER[(ORDER.indexOf(getMode()) + 1) % ORDER.length];
    setMode(next);
    apply(next);
  }

  // Re-resolve when the OS theme changes while we're following it
  window.matchMedia?.("(prefers-color-scheme: dark)").addEventListener(
    "change",
    () => {
      if (getMode() === "auto") apply("auto");
    },
  );

  document.addEventListener("click", (e) => {
    if (e.target.closest(".theme-toggle")) {
      e.preventDefault();
      cycleTheme();
    }
  });

  apply(getMode());
  window.cycleTheme = cycleTheme;
})();

// Click-to-copy functionality for command inputs
(() => {
  async function copyToClipboard(input) {
    input.select();
    input.setSelectionRange(0, 99999);

    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(input.value);
        return true;
      }
    } catch {
      // Keep text selected for manual copy
    }
    return false;
  }

  function showCopyFeedback(element, success) {
    if (!success) return;

    const label = element.closest(".install-cmd")?.querySelector("span");
    if (!label) return;

    const originalText = label.textContent;
    label.textContent = "Copied!";
    label.style.color = "#10b981";

    setTimeout(() => {
      label.textContent = originalText;
      label.style.color = "";
    }, 1500);
  }

  // Setup copy handlers using event delegation
  document.addEventListener("click", async (e) => {
    const input = e.target.closest('input[readonly][onclick*="select"]');
    if (input) {
      input.removeAttribute("onclick");
      const success = await copyToClipboard(input);
      showCopyFeedback(input, success);
    }
  });
})();

// Formula search functionality
(() => {
  let searchTimeout = null;
  const searchInput = document.getElementById("formula-search");
  if (!searchInput) return;

  function fuzzyMatch(needle, haystack) {
    if (!needle) return true;

    needle = needle.toLowerCase();
    haystack = haystack.toLowerCase();

    let j = 0;
    for (let i = 0; i < needle.length; i++) {
      const char = needle[i];
      j = haystack.indexOf(char, j);
      if (j === -1) return false;
      j++;
    }
    return true;
  }

  function performSearch() {
    const searchTerm = searchInput.value.trim();
    const cards = document.querySelectorAll(".formula-card");

    cards.forEach((card) => {
      const text = `${card.querySelector("h3")?.textContent || ""} ${
        card.querySelector("p")?.textContent || ""
      }`;
      card.style.display =
        !searchTerm || fuzzyMatch(searchTerm, text) ? "" : "none";
    });
  }
  searchInput.addEventListener("input", () => {
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(performSearch, 300);
  });

  searchInput.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      e.preventDefault();
      searchInput.value = "";
      performSearch();
    }
  });
})();
