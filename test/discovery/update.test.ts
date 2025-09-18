import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployDiscoveryWithProvidersFixture } from "./fixtures";

describe("FlyoverDiscovery updateProvider", () => {
  it("updates name and apiBaseUrl and emits event", async () => {
    const { discovery, fullLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const connected = discovery.connect(fullLp);

    const newName = "Modified Name";
    const newUrl = "https://modified.example";

    await expect(connected.updateProvider(newName, newUrl))
      .to.emit(discovery, "ProviderUpdate")
      .withArgs(fullLp.address, newName, newUrl);

    const updated = await discovery.getProvider(fullLp.address);
    expect(updated.name).to.equal(newName);
    expect(updated.apiBaseUrl).to.equal(newUrl);
  });

  it("reverts on invalid input (empty name or url)", async () => {
    const { discovery, fullLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const connected = discovery.connect(fullLp);
    await expect(
      connected.updateProvider("", "x")
    ).to.be.revertedWithCustomError(discovery, "InvalidProviderData");
    await expect(
      connected.updateProvider("x", "")
    ).to.be.revertedWithCustomError(discovery, "InvalidProviderData");
  });

  it("reverts if unregistered address calls update", async () => {
    const { discovery, signers } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const stranger = signers[0];
    await expect(
      discovery.connect(stranger).updateProvider("n", "u")
    ).to.be.revertedWithCustomError(discovery, "ProviderNotRegistered");
  });
});
