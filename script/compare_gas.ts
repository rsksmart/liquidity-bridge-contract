#!/usr/bin/env ts-node

import { execSync } from "child_process";
import { readFileSync, writeFileSync } from "fs";

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

const previousCommit = execSync("git rev-parse HEAD~1").toString().trim();

const currentGasSnapshotContent = readFileSync(".gas-snapshot", "utf-8");
const previousGasSnapshotContent = execSync(
  `git show ${previousCommit}:.gas-snapshot`
)
  .toString()
  .trim();

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

const outputFilePath = "gas_comparison.csv";
writeFileSync(outputFilePath, csvContent);
console.log(`Gas comparison written to ${outputFilePath}`);
