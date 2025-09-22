// Dark mode toggle functionality
(() => {
  const STORAGE_KEY = "theme";

  function getStoredTheme() {
    try {
      return localStorage.getItem(STORAGE_KEY);
    } catch {
      return null;
    }
  }

  function setStoredTheme(theme) {
    try {
      localStorage.setItem(STORAGE_KEY, theme);
    } catch {
      // Ignore storage failures
    }
  }

  function getSystemTheme() {
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  }

  function getCurrentTheme() {
    return getStoredTheme() || getSystemTheme() || "light";
  }

  function applyTheme(theme) {
    document.documentElement.classList.toggle("dark", theme === "dark");
    const toggle = document.querySelector(".theme-toggle");
    if (toggle) {
      toggle.innerHTML = theme === "dark" ? "☀️" : "🌙";
      toggle.setAttribute(
        "aria-label",
        theme === "dark" ? "Switch to light mode" : "Switch to dark mode",
      );
    }
  }

  function toggleTheme() {
    const currentTheme = getCurrentTheme();
    const newTheme = currentTheme === "dark" ? "light" : "dark";
    setStoredTheme(newTheme);
    applyTheme(newTheme);
  }

  // Watch for system theme changes
  const mediaQuery = window.matchMedia?.("(prefers-color-scheme: dark)");
  mediaQuery?.addEventListener("change", (e) => {
    if (!getStoredTheme()) {
      applyTheme(e.matches ? "dark" : "light");
    }
  });

  // Theme toggle click handler
  document.addEventListener("click", (e) => {
    if (e.target.closest(".theme-toggle")) {
      e.preventDefault();
      toggleTheme();
    }
  });

  // Initialize theme
  applyTheme(getCurrentTheme());
  window.toggleTheme = toggleTheme;
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
