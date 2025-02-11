import { ethers } from "hardhat";
import path from "path";
import fs from "fs";
import * as helpers from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { changeMultisigOwner } from "../scripts/deployment-utils/change-multisig-owner";
import { expect } from "chai";
import { DeploymentConfig, read } from "../scripts/deployment-utils/deploy";
import multsigInfoJson from "../multisig-owners.json";
import { GnosisSafe, LiquidityBridgeContract } from "../typechain-types";
import { deployUpgradeLibraries } from "../scripts/deployment-utils/upgrade-proxy";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

type MultisigInfo = Record<
  string,
  {
    address: string;
    owners?: string[];
  }
>;

type PartialAdminData = Partial<{
  admin: {
    address: string;
  };
}>;

const { FORK_NETWORK_NAME, FORK_NETWORK_ID } = process.env;
const multsigInfo: MultisigInfo = multsigInfoJson;

describe("Should change LBC owner to the multisig.ts", function () {
  it("Should change the owner", async () => {
    await checkForkedNetwork();
    const networkName = FORK_NETWORK_NAME ?? "rskTestnet";
    const networkId = FORK_NETWORK_ID ?? "31";

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

    const safeContract = await ethers.getContractAt("GnosisSafe", safeAddress);

    await expect(
      multisigExecProviderStatusChangeTransaction(safeContract, lbc)
    ).to.eventually.be.equal(true);

    await expect(
      multisigExecUpgradeTransaction(
        safeContract,
        impersonatedSigner,
        lbc,
        networkName,
        networkId
      )
    ).to.eventually.be.equal(false);

    await expect(
      multisigExecUpgradeTransaction(
        safeContract,
        null,
        lbc,
        networkName,
        networkId
      )
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
  safeContract: GnosisSafe,
  lbc: LiquidityBridgeContract
): Promise<boolean> {
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
  safeContract: GnosisSafe,
  signer: HardhatEthersSigner | null,
  lbc: LiquidityBridgeContract,
  networkName: string,
  networkId: string
): Promise<boolean> {
  const opts = { verbose: true };
  const libs = await deployUpgradeLibraries(networkName, opts);

  const NewLbcFactory = await ethers.getContractFactory(
    "LiquidityBridgeContractV2",
    {
      libraries: {
        QuotesV2: libs.quotesV2,
        BtcUtils: libs.btcUtils,
        SignatureValidator: libs.signatureValidator,
      },
    }
  );

  const newLbcDeployed = await NewLbcFactory.deploy();
  const newLbcAddress = await newLbcDeployed.getAddress();

  const adminAddress = getAdminAddress(networkId);

  if (!adminAddress) {
    throw new Error("Admin address not found.");
  }

  const adminContract = await ethers.getContractAt(
    "LiquidityBridgeContractAdmin",
    adminAddress
  );
  const proxyAddress = await lbc.getAddress();

  let result = false;

  if (!signer) {
    const callData = adminContract.interface.encodeFunctionData("upgrade", [
      proxyAddress,
      newLbcAddress,
    ]);
    console.info("Call data:", callData);

    const nonce = await safeContract.nonce();
    console.info("Nonce:", nonce);

    const txData = {
      to: adminAddress,
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

    result = Boolean(
      await safeContract.execTransaction(
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
      )
    );
  } else {
    await expect(
      adminContract.connect(signer).upgrade(proxyAddress, newLbcAddress)
    ).to.revertedWith("Ownable: caller is not the owner");
    return false;
  }

  return Boolean(result);
}

function getAdminAddress(networkId: string): string | undefined {
  try {
    const filePath = path.join(
      __dirname,
      "../",
      `.openzeppelin/unknown-${networkId}.json`
    );

    const data: PartialAdminData = JSON.parse(
      fs.readFileSync(filePath, "utf8")
    ) as PartialAdminData;

    const adminAddress = data.admin?.address;
    if (adminAddress) {
      return adminAddress;
    } else {
      console.error("Admin address not found in the file.");
      return undefined;
    }
  } catch (err) {
    console.error("Error reading the JSON file:", err);
    return undefined;
  }
}
