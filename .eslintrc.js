module.exports = {
  env: {
    browser: false,
    commonjs: true,
    es2021: true,
    mocha: true,
  },
  globals: {
    artifacts: "readonly",
    assert: "readonly",
    contract: "readonly",
    ethers: "readonly",
    web3: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "airbnb-base",
    "prettier",
  ],

  parser: "@typescript-eslint/parser",
  plugins: ["@typescript-eslint"],
  root: true,
  overrides: [
    {
      files: ["test/**/*.js", "test/**/*.ts"],
      rules: {
        "@typescript-eslint/no-var-requires": "off",
        "func-names": "off",
        "no-unused-expressions": "off",
      },
    },
  ],
  parserOptions: {
    ecmaVersion: "latest",
  },
  rules: {
    "@typescript-eslint/no-unused-vars": [
      "error",
      { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
    ],
    "no-unused-vars": [
      "error",
      { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
    ],
    "no-underscore-dangle": "off",
    "no-console": "off",
  },
};
