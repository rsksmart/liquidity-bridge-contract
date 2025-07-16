import hre, { ethers } from "hardhat";
import { expect } from "chai";
import { GnosisSafe, GnosisSafeProxyFactory } from "../typechain-types";
import { ContractTransactionResponse } from "ethers";
import { deployLbcProxy } from "../scripts/deployment-utils/deploy-proxy";
import { changeMultisigOwner } from "../scripts/deployment-utils/change-multisig-owner";
import multisigOwners from "../multisig-owners.json";
import { REGISTER_LP_PARAMS } from "./utils/constants";

describe("Safe Wallet Deployment", function async() {
  async function safeInitialize() {
    const [signer1, signer2] = await ethers.getSigners();

    const SafeSingleton = await ethers.getContractFactory("GnosisSafe");
    const safeSingleton = await SafeSingleton.deploy();
    await safeSingleton.waitForDeployment();

    const ProxyFactory = await ethers.getContractFactory(
      "GnosisSafeProxyFactory"
    );
    const proxyFactory = await ProxyFactory.deploy();
    await proxyFactory.waitForDeployment();

    return { signer1, signer2, safeSingleton, proxyFactory };
  }

  async function createTestWallet(
    singletonAddress: string,
    proxyFactory: GnosisSafeProxyFactory & {
      deploymentTransaction(): ContractTransactionResponse;
    },
    safeSingleton: GnosisSafe & {
      deploymentTransaction(): ContractTransactionResponse;
    },
    signers: string[]
  ) {
    const initializer = safeSingleton.interface.encodeFunctionData("setup", [
      signers,
      2,
      ethers.ZeroAddress,
      "0x",
      ethers.ZeroAddress,
      ethers.ZeroAddress,
      0,
      ethers.ZeroAddress,
    ]);

    const tx = await proxyFactory.createProxy(singletonAddress, initializer);
    const receipt = await tx.wait();

    if (!receipt) {
      throw new Error("No receipt");
    }
    const proxyAddress = receipt.logs
      .map((log) => proxyFactory.interface.parseLog(log))
      .find((event) => event?.name === "ProxyCreation")?.args.proxy as string;

    const testSafeWallet = await ethers.getContractAt(
      "GnosisSafe",
      proxyAddress
    );

    return testSafeWallet;
  }

  it("should create a Safe wallet with two signers", async function () {
    const { signer1, signer2, safeSingleton, proxyFactory } =
      await safeInitialize();

    const singletonAddress = await safeSingleton.getAddress();

    const testSafeWallet = await createTestWallet(
      singletonAddress,
      proxyFactory,
      safeSingleton,
      [signer1.address, signer2.address]
    );

    const owners = await testSafeWallet.getOwners();
    expect(owners.length).to.equal(2);
    expect(owners[0]).to.equal(signer1.address);
    expect(owners[1]).to.equal(signer2.address);
  });

  describe("LBC Ownership change", function () {
    it("should change the ownership of LBC", async function () {
      const { signer1, signer2, safeSingleton, proxyFactory } =
        await safeInitialize();

      const singletonAddress = await safeSingleton.getAddress();

      const testSafeWallet = await createTestWallet(
        singletonAddress,
        proxyFactory,
        safeSingleton,
        [signer1.address, signer2.address]
      );

      const deployed = await deployLbcProxy(hre.network.name, {
        verbose: false,
      });
      const proxyAddress = deployed.address;
      const lbc = await ethers.getContractAt(
        "LiquidityBridgeContract",
        proxyAddress
      );
      const result = await lbc.queryFilter(lbc.getEvent("Initialized"));
      expect(deployed.deployed).to.be.eq(true);
      expect(result.length).length.equal(1);
      await expect(lbc.owner()).eventually.to.equal(signer1.address);

      const tx = await lbc.connect(signer2).register(...REGISTER_LP_PARAMS);
      await tx.wait();

      const safeAddress = await testSafeWallet.getAddress();
      multisigOwners.hardhat.owners = [signer1.address, signer2.address];

      await changeMultisigOwner(safeAddress);

      await expect(
        lbc.connect(signer1).setProviderStatus(1, true)
      ).to.be.revertedWith("LBC005");

      await expect(lbc.owner()).eventually.to.equal(safeAddress);
    });
  });
});
