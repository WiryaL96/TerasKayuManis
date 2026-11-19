export function useDashboardPreferences() {
  const collapsed = useState("dashboard-sidebar-collapsed", () => false);
  const theme = useState<"light" | "dark">("dashboard-theme", () => "light");
  onMounted(() => {
    try {
      const saved = localStorage.getItem("tkm-sidebar");
      collapsed.value = saved
        ? saved === "collapsed"
        : window.matchMedia("(max-width: 1100px)").matches;
      theme.value =
        localStorage.getItem("tkm-dashboard-theme") === "dark"
          ? "dark"
          : "light";
    } catch {
      /* Storage can be blocked; the controls still work in memory. */
    }
  });
  function toggleCollapsed() {
    collapsed.value = !collapsed.value;
    try {
      localStorage.setItem(
        "tkm-sidebar",
        collapsed.value ? "collapsed" : "expanded",
      );
    } catch {}
  }
  function toggleTheme() {
    theme.value = theme.value === "dark" ? "light" : "dark";
    try {
      localStorage.setItem("tkm-dashboard-theme", theme.value);
    } catch {}
  }
  return { collapsed, theme, toggleCollapsed, toggleTheme };
}
