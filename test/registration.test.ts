import hre from "hardhat";
import { ethers } from "hardhat";
import {
  LP_COLLATERAL,
  MIN_COLLATERAL_TEST,
  REGISTER_LP_PARAMS,
} from "./utils/constants";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployContract } from "../scripts/deployment-utils/utils";
import { deployLbcFixture } from "./utils/fixtures";

describe("LiquidityBridgeContractV2 registration process should", () => {
  it("register liquidity provider successfully", async () => {
    const fixtureResult = await loadFixture(deployLbcFixture);
    const lpAccount = fixtureResult.accounts[0];
    let lbc = fixtureResult.lbc;

    const previousCollateral = await lbc.getCollateral(lpAccount);
    lbc = lbc.connect(lpAccount);

    const tx = await lbc.register(...REGISTER_LP_PARAMS);
    await tx.wait();
    const currentCollateral = await lbc.getCollateral(lpAccount);

    await expect(tx)
      .to.emit(lbc, "Register")
      .withArgs(1n, lpAccount.address, LP_COLLATERAL);
    expect(2n * (currentCollateral - previousCollateral)).to.be.eq(
      LP_COLLATERAL
    );
  });

  it("fail on register if bad parameters", async () => {
    const { lbc } = await loadFixture(deployLbcFixture);
    const cases = [
      {
        name: "",
        url: "http://localhost/api",
        status: true,
        type: "both",
        error: "LBC010",
      },
      {
        name: "First contract",
        url: "",
        status: true,
        type: "both",
        error: "LBC017",
      },
      {
        name: "First contract",
        url: "http://localhost/api",
        status: true,
        type: "",
        error: "LBC018",
      },
    ];

    for (const testCase of cases) {
      await expect(
        lbc.register(
          testCase.name,
          testCase.url,
          testCase.status,
          testCase.type,
          { value: LP_COLLATERAL }
        )
      ).to.be.revertedWith(testCase.error);
    }
  });

  it("fail when Liquidity provider is already registered", async () => {
    const fixtureResult = await loadFixture(deployLbcFixture);
    const lpAccount = fixtureResult.accounts[5];
    const lbc = fixtureResult.lbc.connect(lpAccount);

    const tx = await lbc.register(...REGISTER_LP_PARAMS);
    await expect(tx)
      .to.emit(lbc, "Register")
      .withArgs(1n, lpAccount.address, LP_COLLATERAL);
    await expect(lbc.register(...REGISTER_LP_PARAMS)).to.revertedWith("LBC070");
  });

  it("fail on register if not deposit the minimum collateral", async () => {
    const { lbc } = await loadFixture(deployLbcFixture);
    await expect(
      lbc.register("First contract", "http://localhost/api", true, "both", {
        value: 0n,
      })
    ).to.be.revertedWith("LBC008");
  });

  it("not register lp with not enough collateral", async () => {
    const { lbc } = await loadFixture(deployLbcFixture);
    await expect(
      lbc.register("First contract", "http://localhost/api", true, "both", {
        value: MIN_COLLATERAL_TEST * 2n - 1n,
      })
    ).to.be.revertedWith("LBC008");
  });

  it("fail to register liquidity provider from a contract", async () => {
    const fixtureResult = await loadFixture(deployLbcFixture);
    const accounts = fixtureResult.accounts;
    const lpSigner = accounts[9];
    const notLpSigner = accounts[8];
    let lbc = fixtureResult.lbc;
    const deploymentInfo = await deployContract("Mock", hre.network.name);
    let mockContract = await ethers.getContractAt(
      "Mock",
      deploymentInfo.address
    );
    const lbcAddress = await lbc.getAddress();

    lbc = lbc.connect(lpSigner);
    const tx = await lbc.register(...REGISTER_LP_PARAMS);
    await tx.wait();

    mockContract = await mockContract.connect(lpSigner);
    await expect(
      mockContract.callRegister(lbcAddress, { value: LP_COLLATERAL })
    ).to.revertedWith("LBC003");

    mockContract = await mockContract.connect(notLpSigner);
    await expect(
      mockContract.callRegister(lbcAddress, { value: LP_COLLATERAL })
    ).to.revertedWith("LBC003");
  });
});
