#!/usr/bin/env ts-node

import { execSync } from "child_process";
import { existsSync, readFileSync, writeFileSync } from "fs";

type GasValues = Partial<Record<string, number>>;

function readGasValues(content: string): GasValues {
  const gasValues: GasValues = {};
  const lines = content.split("\n");
  const gasLinePattern = /(.*) \(gas: ([0-9]+)\)/;

  lines.forEach((line) => {
    const match = gasLinePattern.exec(line);
    if (match) {
      const testName = match[1];
      const gas = Number.parseInt(match[2], 10);
      gasValues[testName] = gas;
    }
  });

  return gasValues;
}

function parseArgs(): { baseRef: string; baseFile?: string } {
  const args = process.argv.slice(2);
  let baseRef = "HEAD~1";
  let baseFile: string | undefined;

  for (const arg of args) {
    if (arg.startsWith("--base-file=")) {
      baseFile = arg.split("=")[1];
    } else if (arg.startsWith("--base=")) {
      baseRef = arg.split("=")[1];
    }
  }

  return { baseRef, baseFile };
}

function loadPreviousSnapshot(baseRef: string, baseFile?: string): string {
  if (baseFile) {
    if (!existsSync(baseFile)) {
      console.error(`Error: base file not found: ${baseFile}`);
      process.exit(1);
    }
    return readFileSync(baseFile, "utf-8");
  }

  try {
    const commit = execSync(`git rev-parse ${baseRef}`, {
      stdio: ["pipe", "pipe", "pipe"],
    })
      .toString()
      .trim();
    return execSync(`git show ${commit}:.gas-snapshot`, {
      stdio: ["pipe", "pipe", "pipe"],
    })
      .toString()
      .trim();
  } catch {
    console.warn(
      `Warning: .gas-snapshot not found in ${baseRef}. Treating previous snapshot as empty.`
    );
    return "";
  }
}

const { baseRef, baseFile } = parseArgs();

const currentGasSnapshotContent = readFileSync(".gas-snapshot", "utf-8");
const previousGasSnapshotContent = loadPreviousSnapshot(baseRef, baseFile);

const currentGasValues = readGasValues(currentGasSnapshotContent);
const previousGasValues = readGasValues(previousGasSnapshotContent);

let csvContent = "Test Name,Current Gas,Previous Gas,Difference\n";
Object.keys(currentGasValues).forEach((testName) => {
  const currentGas = currentGasValues[testName] ?? 0;
  const previousGas = previousGasValues[testName];

  if (previousGas === undefined) {
    csvContent += `${testName},${String(currentGas)},N/A,N/A\n`;
    return;
  }

  const difference = currentGas - previousGas;
  csvContent += `${testName},${String(currentGas)},${String(
    previousGas
  )},${String(difference)}\n`;
});

Object.keys(previousGasValues).forEach((testName) => {
  if (!(testName in currentGasValues)) {
    csvContent += `${testName},REMOVED,${String(
      previousGasValues[testName]
    )},N/A\n`;
  }
});

const outputFilePath = "gas_comparison.csv";
writeFileSync(outputFilePath, csvContent);
console.log(`Gas comparison written to ${outputFilePath}`);
