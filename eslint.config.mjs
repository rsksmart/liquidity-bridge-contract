import globals from "globals";
import pluginJs from "@eslint/js";
import tseslint from "typescript-eslint";

/** @type {import('eslint').Linter.Config[]} */
export default [
  { files: ["**/*.{js,mjs,cjs,ts}"] },
  { languageOptions: { globals: globals.node } },
  {
    ignores: [
      "typechain-types/*",
      "node_modules/*",
      "artifacts/*",
      "cache/*",
      "node_modules/*",
      // should be removed after completing the hardhat migration
      "migrations/*",
      "truffle*",
      "integration-test/*",
      "testHashQuote.js",
      "testRefundPegout.js",
      "testRegisterPegout.js",
      "testBridge.js",
    ],
  },
  pluginJs.configs.recommended,
  ...tseslint.configs.recommended,
];
