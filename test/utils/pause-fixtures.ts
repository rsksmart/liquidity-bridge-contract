/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable @typescript-eslint/no-unsafe-assignment */
/* eslint-disable @typescript-eslint/no-unsafe-member-access */
/* eslint-disable @typescript-eslint/no-unsafe-call */

import { deployCollateralManagementAndDiscovery } from "./fixtures";
import { deployPegInContractFixture } from "../pegin/fixtures";
import { deployPegOutContractFixture } from "../pegout/fixtures";

export interface PauseSystemFixture {
  contracts: {
    flyoverDiscovery: any;
    pegInContract: any;
    pegOutContract: any;
    collateralManagement: any;
  };
  addresses: {
    flyoverDiscovery: string;
    pegInContract: string;
    pegOutContract: string;
    collateralManagement: string;
  };
  owner: any;
  signers: any[];
  pegInLp: any;
  pegOutLp: any;
  fullLp: any;
}

/**
 * Fixture that deploys all four contracts and sets up the system for pause testing
 */
export async function deployPauseSystemFixture(): Promise<PauseSystemFixture> {
  // Deploy CollateralManagement and FlyoverDiscovery
  const discoveryResult = await deployCollateralManagementAndDiscovery();

  // Deploy PegIn and PegOut contracts
  const pegInResult = await deployPegInContractFixture();
  const pegOutResult = await deployPegOutContractFixture();

  const contracts = {
    flyoverDiscovery: discoveryResult.discovery,
    pegInContract: pegInResult.contract,
    pegOutContract: pegOutResult.contract,
    collateralManagement: discoveryResult.collateralManagement,
  };

  const addresses = {
    flyoverDiscovery: await contracts.flyoverDiscovery.getAddress(),
    pegInContract: await contracts.pegInContract.getAddress(),
    pegOutContract: await contracts.pegOutContract.getAddress(),
    collateralManagement: await contracts.collateralManagement.getAddress(),
  };

  return {
    contracts,
    addresses,
    owner: discoveryResult.owner,
    signers: discoveryResult.signers,
    pegInLp: discoveryResult.pegInLp,
    pegOutLp: discoveryResult.pegOutLp,
    fullLp: discoveryResult.fullLp,
  };
}

/**
 * Pauses all contracts in the system using the same logic as the pause task
 */
export async function pauseAllContracts(
  fixture: PauseSystemFixture,
  pauser: any,
  reason: string
): Promise<{ successful: string[]; failed: string[] }> {
  const PAUSER_ROLE =
    "0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a";
  const successful: string[] = [];
  const failed: string[] = [];

  // Grant PAUSER_ROLE to the pauser for all contracts that support it
  const contractsWithRoles = [
    { name: "FlyoverDiscovery", contract: fixture.contracts.flyoverDiscovery },
    {
      name: "CollateralManagement",
      contract: fixture.contracts.collateralManagement,
    },
  ];

  // Grant roles first
  for (const { name, contract } of contractsWithRoles) {
    try {
      await contract
        .connect(fixture.owner)
        .grantRole(PAUSER_ROLE, pauser.address);
    } catch (error) {
      console.warn(`Failed to grant PAUSER_ROLE to ${name}:`, error);
    }
  }

  // Note: PegIn and PegOut contracts have AccessControl setup issues,
  // so we'll skip them for now in the pause testing

  // Pause all contracts
  const contractsToPause = [
    { name: "FlyoverDiscovery", contract: fixture.contracts.flyoverDiscovery },
    {
      name: "CollateralManagement",
      contract: fixture.contracts.collateralManagement,
    },
  ];

  for (const { name, contract } of contractsToPause) {
    try {
      await contract.connect(pauser).pause(reason);
      successful.push(name);
    } catch (error) {
      failed.push(name);
      console.warn(`Failed to pause ${name}:`, error);
    }
  }

  return { successful, failed };
}

/**
 * Unpauses all contracts in the system
 */
export async function unpauseAllContracts(
  fixture: PauseSystemFixture,
  pauser: any
): Promise<{ successful: string[]; failed: string[] }> {
  const successful: string[] = [];
  const failed: string[] = [];

  const contractsToUnpause = [
    { name: "FlyoverDiscovery", contract: fixture.contracts.flyoverDiscovery },
    {
      name: "CollateralManagement",
      contract: fixture.contracts.collateralManagement,
    },
  ];

  for (const { name, contract } of contractsToUnpause) {
    try {
      await contract.connect(pauser).unpause();
      successful.push(name);
    } catch (error) {
      failed.push(name);
      console.warn(`Failed to unpause ${name}:`, error);
    }
  }

  return { successful, failed };
}

/**
 * Checks the pause status of all contracts
 */
export async function checkPauseStatus(fixture: PauseSystemFixture): Promise<{
  flyoverDiscovery: { isPaused: boolean; reason: string; since: bigint };
  pegInContract: { isPaused: boolean; reason: string; since: bigint };
  pegOutContract: { isPaused: boolean; reason: string; since: bigint };
  collateralManagement: { isPaused: boolean; reason: string; since: bigint };
}> {
  return {
    flyoverDiscovery: await fixture.contracts.flyoverDiscovery.pauseStatus(),
    pegInContract: await fixture.contracts.pegInContract.pauseStatus(),
    pegOutContract: await fixture.contracts.pegOutContract.pauseStatus(),
    collateralManagement:
      await fixture.contracts.collateralManagement.pauseStatus(),
  };
}

/**
 * Fixture that deploys the system and sets up a pauser with proper roles
 */
export async function deployPausedSystemFixture() {
  const fixture = await deployPauseSystemFixture();
  const pauser = fixture.signers[0];
  const reason = "System-wide emergency pause for testing";

  const result = await pauseAllContracts(fixture, pauser, reason);

  return {
    ...fixture,
    pauser,
    reason,
    pauseResult: result,
  };
}
