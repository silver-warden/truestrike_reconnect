const manifest = { "name": "LG2 Controller Fix" };
const API_VERSION = 2;
const internalAPIConnection =
  window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
  throw new Error(
    "[@decky/api]: Failed to connect to the loader as the loader API was not initialized."
  );
}
let api;
try {
  api = internalAPIConnection.connect(API_VERSION, manifest.name);
} catch {
  api = internalAPIConnection.connect(1, manifest.name);
}
const definePlugin = (fn) => {
  return (...args) => {
    return fn(...args);
  };
};
var index = definePlugin(() => {
  return {
    name: "LG2 Controller Fix",
    titleView: SP_JSX.jsx("div", { children: "LG2 Controller Fix" }),
    content: SP_JSX.jsx("div", {
      style: { padding: "1rem" },
      children:
        "Controller watchdog installed. It checks InputPlumber every minute and restarts it if the Legion controllers are attached but no virtual gamepad is present.",
    }),
  };
});

export { index as default };
