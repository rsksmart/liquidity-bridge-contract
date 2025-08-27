import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { deployDiscoveryFixture } from "./fixtures";
import { ProviderType } from "../utils/constants";

describe("FlyoverDiscovery NotEOA checks", () => {
  it("reverts when a contract calls register (NotEOA)", async () => {
    const { discovery, MIN_COLLATERAL } = await loadFixture(
      deployDiscoveryFixture
    );
    const RegisterCaller = await ethers.getContractFactory("RegisterCaller");
    const caller = await RegisterCaller.deploy();
    await caller.waitForDeployment();
    await expect(
      caller.callRegister(
        await discovery.getAddress(),
        "N",
        "U",
        true,
        ProviderType.PegIn,
        { value: MIN_COLLATERAL }
      )
    ).to.be.revertedWithCustomError(discovery, "NotEOA");
  });
});
