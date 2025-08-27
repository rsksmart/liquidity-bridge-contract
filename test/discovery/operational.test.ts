import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployDiscoveryWithProvidersFixture } from "./fixtures";
import { ProviderType } from "../utils/constants";

describe("FlyoverDiscovery operational checks", () => {
  it("isOperational returns true only for providers with peg-in collateral", async () => {
    const { discovery, pegInLp, fullLp, pegOutLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );

    expect(
      await discovery.isOperational(ProviderType.PegIn, pegInLp.address)
    ).to.equal(true);
    expect(
      await discovery.isOperational(ProviderType.PegIn, fullLp.address)
    ).to.equal(true);
    expect(
      await discovery.isOperational(ProviderType.PegIn, pegOutLp.address)
    ).to.equal(false);
  });

  it("isOperationalForPegout returns true only for providers with peg-out collateral", async () => {
    const { discovery, pegInLp, fullLp, pegOutLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    expect(await discovery.isOperationalForPegout(pegOutLp.address)).to.equal(
      true
    );
    expect(await discovery.isOperationalForPegout(fullLp.address)).to.equal(
      true
    );
    expect(await discovery.isOperationalForPegout(pegInLp.address)).to.equal(
      false
    );
  });

  it("reflects minCollateral changes in operational status", async () => {
    const { discovery, owner, fullLp, MIN_COLLATERAL } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );

    // Initially true
    expect(
      await discovery.isOperational(ProviderType.PegIn, fullLp.address)
    ).to.equal(true);
    expect(await discovery.isOperationalForPegout(fullLp.address)).to.equal(
      true
    );

    // Increase threshold above provided collateral for each side
    await discovery.connect(owner).setMinCollateral(MIN_COLLATERAL + 1n);

    expect(
      await discovery.isOperational(ProviderType.PegIn, fullLp.address)
    ).to.equal(false);
    expect(await discovery.isOperationalForPegout(fullLp.address)).to.equal(
      false
    );
  });
});
