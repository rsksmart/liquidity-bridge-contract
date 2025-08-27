import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployDiscoveryFixture } from "./fixtures";

describe("FlyoverDiscovery admin controls", () => {
  it("setMinCollateral is restricted to DEFAULT_ADMIN_ROLE", async () => {
    const { discovery, signers } = await loadFixture(deployDiscoveryFixture);
    const nonAdmin = signers[0];
    await expect(
      discovery.connect(nonAdmin).setMinCollateral(123n)
    ).to.be.revertedWithCustomError(
      discovery,
      "AccessControlUnauthorizedAccount"
    );
  });

  it("admin can setMinCollateral and value is readable", async () => {
    const { discovery, owner } = await loadFixture(deployDiscoveryFixture);
    const before = await discovery.getMinCollateral();
    const next = before + 1n;
    await discovery.connect(owner).setMinCollateral(next);
    expect(await discovery.getMinCollateral()).to.equal(next);
  });
});
