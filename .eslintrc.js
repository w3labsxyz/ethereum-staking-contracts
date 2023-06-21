module.exports = {
  env: {
    browser: false,
    commonjs: true,
    es2021: true,
    mocha: true,
  },
  globals: {
    artifacts: "readonly",
    contract: "readonly",
    assert: "readonly",
    web3: true,
  },
  extends: ["airbnb-base", "prettier"],
  overrides: [
    {
      files: ["test/**/*.test.js"],
      rules: {
        "func-names": "off",
      },
    },
  ],
  parserOptions: {
    ecmaVersion: "latest",
  },
  rules: {
    "no-unused-vars": [
      "error",
      { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
    ],
    "no-underscore-dangle": "off",
  },
};
