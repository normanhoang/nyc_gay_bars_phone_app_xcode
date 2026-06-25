// lib/stats.ts imports VisitsContext, which imports AsyncStorage — mock the
// native module so the pure functions can be tested in Node.
jest.mock("@react-native-async-storage/async-storage", () =>
  require("@react-native-async-storage/async-storage/jest/async-storage-mock"),
);
