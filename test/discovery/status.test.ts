import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployDiscoveryWithProvidersFixture } from "./fixtures";

describe("FlyoverDiscovery setProviderStatus", () => {
  it("allows provider to disable and enable itself", async () => {
    const { discovery, pegOutLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const connected = discovery.connect(pegOutLp);

    await connected.setProviderStatus(2, false);
    let provider = await discovery.getProvider(pegOutLp.address);
    expect(provider.status).to.equal(false);

    await connected.setProviderStatus(2, true);
    provider = await discovery.getProvider(pegOutLp.address);
    expect(provider.status).to.equal(true);
  });

  it("allows owner to toggle provider status", async () => {
    const { discovery, owner, pegInLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const connected = discovery.connect(owner);

    await connected.setProviderStatus(1, false);
    let provider = await discovery.getProvider(pegInLp.address);
    expect(provider.status).to.equal(false);

    await connected.setProviderStatus(1, true);
    provider = await discovery.getProvider(pegInLp.address);
    expect(provider.status).to.equal(true);
  });

  it("reverts for unauthorized address", async () => {
    const { discovery, signers } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const stranger = signers[0];
    await expect(
      discovery.connect(stranger).setProviderStatus(1, false)
    ).to.be.revertedWithCustomError(discovery, "NotAuthorized");
  });
});
