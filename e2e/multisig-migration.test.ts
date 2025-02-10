import { ethers } from "hardhat";
import * as helpers from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { changeMultisigOwner } from "../scripts/deployment-utils/change-multisig-owner";
import { expect } from "chai";
import { DeploymentConfig, read } from "../scripts/deployment-utils/deploy";
import multsigInfoJson from "../multisig-owners.json";
import { LiquidityBridgeContract } from "../typechain-types";

type MultisigInfo = Record<
  string,
  {
    address: string;
    owners?: string[];
  }
>;

const { FORK_NETWORK_NAME } = process.env;

const multsigInfo: MultisigInfo = multsigInfoJson;

describe("Should change LBC owner to the multisig.ts", function () {
  it("Should change the owner", async () => {
    await checkForkedNetwork();
    const networkName = FORK_NETWORK_NAME ?? "rskTestnet";
    console.info("Network name:", networkName);

    const lbcName = "LiquidityBridgeContract";
    const addresses: Partial<DeploymentConfig> = read();
    const networkDeployments: Partial<DeploymentConfig[string]> | undefined =
      addresses[networkName];
    const lbcAddress = networkDeployments?.LiquidityBridgeContract?.address;
    const safeAddress = multsigInfo[networkName].address;

    if (!lbcAddress) {
      throw new Error(
        "LiquidityBridgeContract proxy deployment info not found"
      );
    }
    console.info(`LBC address: ${lbcAddress}`);
    console.info(`Safe address: ${safeAddress}`);

    const lbc = await ethers.getContractAt(lbcName, lbcAddress);

    const lbcOwner = await lbc.owner();
    console.info("LBC owner:", lbcOwner);
    await helpers.impersonateAccount(lbcOwner);
    const impersonatedSigner = await ethers.getSigner(lbcOwner);

    await expect(
      changeMultisigOwner(safeAddress, "rskTestnet", impersonatedSigner)
    ).to.not.be.reverted;
    const newLbcOwner = await lbc.owner();
    console.info("New LBC owner:", newLbcOwner);

    await expect(
      lbc.connect(impersonatedSigner).setProviderStatus(1, false)
    ).to.be.revertedWith("LBC005");

    expect(
      multisigExecProviderStatusChangeTransaction(safeAddress, lbc)
    ).to.eventually.be.equal(true);
    expect(
      multisigExecUpgradeTransaction(impersonatedSigner.address, lbc)
    ).to.eventually.be.equal(false);
    expect(
      multisigExecUpgradeTransaction(safeAddress, lbc)
    ).to.eventually.be.equal(true);
  });
});

async function checkForkedNetwork() {
  try {
    await ethers.provider.send("evm_snapshot", []);
  } catch (error) {
    console.error("Not a forked network:", error);
  }
}

function generateConcatenatedSignatures(owners: string[]) {
  const concatenatedSignatures =
    "0x" +
    owners
      .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase())) // SORT owners in ascending order
      .map((owner) => {
        return "0".repeat(24) + owner.slice(2) + "0".repeat(64) + "01";
      })
      .join("");

  return concatenatedSignatures;
}

export async function multisigExecProviderStatusChangeTransaction(
  safeAddress: string,
  lbc: LiquidityBridgeContract
): Promise<boolean> {
  const safeContract = await ethers.getContractAt("GnosisSafe", safeAddress);

  const callData = lbc.interface.encodeFunctionData("setProviderStatus", [
    1,
    false,
  ]);
  console.info("Call data:", callData);

  const nonce = await safeContract.nonce();
  console.info("Nonce:", nonce);

  const txData = {
    to: await lbc.getAddress(),
    value: 0,
    data: callData,
    operation: 0,
    safeTxGas: 0,
    baseGas: 0,
    gasPrice: 0,
    gasToken: ethers.ZeroAddress,
    refundReceiver: ethers.ZeroAddress,
    nonce: nonce,
    signatures: "0x",
  };

  const owners = await safeContract.getOwners();

  const desiredBalance = ethers.toQuantity(ethers.parseEther("100"));

  await helpers.impersonateAccount(owners[0]);
  const impersonateOwner1 = await ethers.getSigner(owners[0]);
  await ethers.provider.send("hardhat_setBalance", [
    impersonateOwner1.address,
    desiredBalance,
  ]);
  await helpers.impersonateAccount(owners[1]);
  const impersonateOwner2 = await ethers.getSigner(owners[1]);
  await ethers.provider.send("hardhat_setBalance", [
    impersonateOwner2.address,
    desiredBalance,
  ]);
  await helpers.impersonateAccount(owners[2]);
  const impersonateOwner3 = await ethers.getSigner(owners[2]);
  await ethers.provider.send("hardhat_setBalance", [
    impersonateOwner3.address,
    desiredBalance,
  ]);

  const transactionHash = await safeContract
    .connect(impersonateOwner1)
    .getTransactionHash(
      txData.to,
      txData.value,
      txData.data,
      txData.operation,
      txData.safeTxGas,
      txData.baseGas,
      txData.gasPrice,
      txData.gasToken,
      txData.refundReceiver,
      txData.nonce
    );
  console.info("Transaction hash:", transactionHash);

  await safeContract.connect(impersonateOwner1).approveHash(transactionHash);
  await safeContract.connect(impersonateOwner2).approveHash(transactionHash);
  await safeContract.connect(impersonateOwner3).approveHash(transactionHash);
  const signature = generateConcatenatedSignatures([
    impersonateOwner1.address,
    impersonateOwner2.address,
    impersonateOwner3.address,
  ]);
  console.info("Signature:", signature);

  txData.signatures = signature;

  const result = await safeContract.execTransaction(
    txData.to,
    txData.value,
    txData.data,
    txData.operation,
    txData.safeTxGas,
    txData.baseGas,
    txData.gasPrice,
    txData.gasToken,
    txData.refundReceiver,
    txData.signatures
  );

  return Boolean(result);
}

export async function multisigExecUpgradeTransaction(
  safeAddress: string,
  lbc: LiquidityBridgeContract
): Promise<boolean> {
  const safeContract = await ethers.getContractAt("GnosisSafe", safeAddress);

  const NewLbcFactory = await ethers.getContractFactory(
    "LiquidityBridgeContractV2"
  );
  const newLbcDeplolyed = await NewLbcFactory.deploy();
  const newLbc = await ethers.getContractAt(
    "LiquidityBridgeContractV2",
    await newLbcDeplolyed.getAddress()
  );
  const newLbcAddress = await newLbc.getAddress();

  const proxyAddress = await lbc.getAddress();
  // @ts-expect-error - The 'upgrade' method exists on the parent contract
  const callData = lbc.interface.encodeFunctionData("upgrade", [
    proxyAddress,
    newLbcAddress,
  ]);
  console.info("Call data:", callData);

  const nonce = await safeContract.nonce();
  console.info("Nonce:", nonce);

  const txData = {
    to: proxyAddress,
    value: 0,
    data: callData,
    operation: 0,
    safeTxGas: 0,
    baseGas: 0,
    gasPrice: 0,
    gasToken: ethers.ZeroAddress,
    refundReceiver: ethers.ZeroAddress,
    nonce: nonce,
    signatures: "0x",
  };

  const owners = await safeContract.getOwners();

  const desiredBalance = ethers.toQuantity(ethers.parseEther("100"));

  await helpers.impersonateAccount(owners[0]);
  const impersonateOwner1 = await ethers.getSigner(owners[0]);
  await ethers.provider.send("hardhat_setBalance", [
    impersonateOwner1.address,
    desiredBalance,
  ]);
  await helpers.impersonateAccount(owners[1]);
  const impersonateOwner2 = await ethers.getSigner(owners[1]);
  await ethers.provider.send("hardhat_setBalance", [
    impersonateOwner2.address,
    desiredBalance,
  ]);
  await helpers.impersonateAccount(owners[2]);
  const impersonateOwner3 = await ethers.getSigner(owners[2]);
  await ethers.provider.send("hardhat_setBalance", [
    impersonateOwner3.address,
    desiredBalance,
  ]);

  const transactionHash = await safeContract
    .connect(impersonateOwner1)
    .getTransactionHash(
      txData.to,
      txData.value,
      txData.data,
      txData.operation,
      txData.safeTxGas,
      txData.baseGas,
      txData.gasPrice,
      txData.gasToken,
      txData.refundReceiver,
      txData.nonce
    );
  console.info("Transaction hash:", transactionHash);

  await safeContract.connect(impersonateOwner1).approveHash(transactionHash);
  await safeContract.connect(impersonateOwner2).approveHash(transactionHash);
  await safeContract.connect(impersonateOwner3).approveHash(transactionHash);
  const signature = generateConcatenatedSignatures([
    impersonateOwner1.address,
    impersonateOwner2.address,
    impersonateOwner3.address,
  ]);
  console.info("Signature:", signature);

  txData.signatures = signature;

  const result = await safeContract.execTransaction(
    txData.to,
    txData.value,
    txData.data,
    txData.operation,
    txData.safeTxGas,
    txData.baseGas,
    txData.gasPrice,
    txData.gasToken,
    txData.refundReceiver,
    txData.signatures
  );

  return Boolean(result);
}
