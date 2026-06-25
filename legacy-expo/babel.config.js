module.exports = function (api) {
  api.cache(true);
  return {
    presets: [
      ["babel-preset-expo", { jsxImportSource: "nativewind" }],
      "nativewind/babel",
    ],
    plugins: [
      // Worklets plugin (reanimated v4) must be listed last.
      "react-native-worklets/plugin",
    ],
  };
};
