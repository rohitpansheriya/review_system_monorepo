module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.json", "tsconfig.dev.json"],
    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*", // Ignore built files.
    "/lib-scripts/**/*", // Ignore compiled dev scripts.
    "/generated/**/*", // Ignore generated files.
    "/src/scripts/**/*", // Ignore dev-only scripts (not in tsconfig.json).
  ],
  plugins: [
    "@typescript-eslint",
    "import",
  ],
  rules: {
    "quotes": ["error", "double"],
    "import/no-unresolved": 0,
    "indent": ["error", 2],
    "max-len": ["error", {"code": 160, "ignoreComments": true, "ignoreUrls": true, "ignoreStrings": true, "ignoreTemplateLiterals": true}],
    "require-jsdoc": 0,
    "valid-jsdoc": 0,
    "@typescript-eslint/no-explicit-any": "warn",
    "object-curly-spacing": ["error", "never"],
  },
};
