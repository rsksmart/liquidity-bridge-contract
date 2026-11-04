import globals from "globals";
import pluginJs from "@eslint/js";
import tseslint from "typescript-eslint";

/** @type {import('eslint').Linter.Config[]} */
export default [
  { files: ["**/*.{js,mjs,cjs,ts}"] },
  { languageOptions: { globals: globals.node } },
  {
    ignores: [
      "eslint.config.mjs",
      // Standalone Node drift-detection utility kept byte-identical across repos;
      // not part of the typed project. See docs/release-drift.md.
      "scripts/check-release-drift.mjs",
      "typechain-types/*",
      "node_modules/*",
      "artifacts/*",
      "cache/*",
      "coverage/*",
      "broadcast/*",
      "out/*",
      "lib/*",
    ],
  },
  pluginJs.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    rules: {
      "@typescript-eslint/no-non-null-assertion": "off",
    },
  },
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
];
