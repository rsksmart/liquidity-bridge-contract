// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {DeployFlyover} from "../../../script/deployment/DeployFlyover.s.sol";
import {IDifferentialAdapter} from "../adapters/IDifferentialAdapter.sol";
import {CandidateAdapter} from "../adapters/CandidateAdapter.sol";
import {ReferenceAdapter} from "../adapters/ReferenceAdapter.sol";

abstract contract DifferentialBase is Test {
    struct CandidateTargets {
        address pegIn;
        address pegOut;
        address collateral;
        address discovery;
    }

    struct NetworkHarness {
        uint256 forkId;
        address referenceTarget;
        address candidatePegInTarget;
        address candidatePegOutTarget;
        address candidateCollateralTarget;
        address candidateDiscoveryTarget;
        IDifferentialAdapter referenceAdapter;
        IDifferentialAdapter candidateAdapter;
    }

    NetworkHarness internal _harness;

    function setUp() public virtual {
        HelperConfig helper = new HelperConfig();
        HelperConfig.DifferentialNetworkConfig memory cfg = helper
            .getDifferentialNetworkConfig();
        _bootstrapNetwork(
            _harness,
            cfg.networkKey,
            cfg.mainnet,
            cfg.pinBlock,
            cfg.btcBlockTime
        );
    }

    function _bootstrapNetwork(
        NetworkHarness storage harness,
        string memory networkKey,
        bool isMainnet,
        uint256 pinBlock,
        uint256 btcBlockTime
    ) internal {
        string memory rpcUrl = _resolveRpcUrl(networkKey);
        harness.forkId = _createForkSafe(rpcUrl, pinBlock);

        vm.selectFork(harness.forkId);

        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory flyoverCfg = helper
            .getFlyoverConfig();
        flyoverCfg.mainnet = isMainnet;
        flyoverCfg.btcBlockTime = btcBlockTime;

        harness.referenceTarget = _resolveReference(networkKey);
        _assertReferenceCompatibility(harness.referenceTarget);
        CandidateTargets memory targets = _deploySplitCandidateFromReference(
            harness.referenceTarget,
            isMainnet,
            btcBlockTime
        );
        harness.candidatePegInTarget = targets.pegIn;
        harness.candidatePegOutTarget = targets.pegOut;
        harness.candidateCollateralTarget = targets.collateral;
        harness.candidateDiscoveryTarget = targets.discovery;

        harness.referenceAdapter = IDifferentialAdapter(
            address(
                new ReferenceAdapter(
                    harness.referenceTarget,
                    flyoverCfg.minimumPegIn,
                    flyoverCfg.dustThreshold
                )
            )
        );
        harness.candidateAdapter = IDifferentialAdapter(
            address(
                new CandidateAdapter(
                    harness.candidatePegInTarget,
                    harness.candidatePegOutTarget,
                    harness.candidateCollateralTarget,
                    harness.candidateDiscoveryTarget,
                    harness.referenceAdapter.getBridgeAddress()
                )
            )
        );
    }

    function _createForkSafe(
        string memory rpcUrl,
        uint256 pinBlock
    ) internal returns (uint256) {
        if (pinBlock == 0) {
            return vm.createFork(rpcUrl);
        }
        try this._createPinnedFork(rpcUrl, pinBlock) returns (uint256 forkId) {
            return forkId;
        } catch {
            return vm.createFork(rpcUrl);
        }
    }

    function _createPinnedFork(
        string memory rpcUrl,
        uint256 pinBlock
    ) external returns (uint256) {
        if (msg.sender != address(this)) revert("only self");
        return vm.createFork(rpcUrl, pinBlock);
    }

    function _resolveReference(
        string memory networkKey
    ) internal view returns (address) {
        string memory addressesJson = vm.readFile("addresses.json");
        string memory key = string.concat(
            ".",
            networkKey,
            ".LiquidityBridgeContract.address"
        );
        return vm.parseJsonAddress(addressesJson, key);
    }

    function _resolveRpcUrl(
        string memory networkKey
    ) internal view returns (string memory) {
        bytes32 networkHash = keccak256(bytes(networkKey));
        if (networkHash == keccak256(bytes("rskMainnet"))) {
            return
                vm.envOr(
                    "MAINNET_RPC_URL",
                    string("https://public-node.rsk.co")
                );
        }
        if (networkHash == keccak256(bytes("rskTestnet"))) {
            return
                vm.envOr(
                    "TESTNET_RPC_URL",
                    string("https://public-node.testnet.rsk.co")
                );
        }
        revert("Unsupported differential network key");
    }

    function _assertReferenceCompatibility(
        address referenceTarget
    ) internal view {
        (bool ok, bytes memory data) = referenceTarget.staticcall(
            abi.encodeWithSignature("version()")
        );
        require(ok && data.length > 0, "Reference must expose version()");

        (bool okBridge, bytes memory bridgeData) = referenceTarget.staticcall(
            abi.encodeWithSignature("bridge()")
        );
        require(
            okBridge && bridgeData.length > 0,
            "Reference must expose bridge()"
        );
    }

    function _deploySplitCandidateFromReference(
        address referenceTarget,
        bool isMainnet,
        uint256 btcBlockTime
    ) internal returns (CandidateTargets memory targets) {
        IDifferentialAdapter refConfig = IDifferentialAdapter(referenceTarget);
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();
        cfg.bridge = refConfig.bridge();
        cfg.minimumCollateral = refConfig.getMinCollateral();
        cfg.rewardPercentage = refConfig.getRewardPercentage();
        cfg.resignDelayBlocks = refConfig.getResignDelayBlocks();
        cfg.mainnet = isMainnet;
        cfg.btcBlockTime = btcBlockTime;

        DeployFlyover deployer = new DeployFlyover();
        DeployFlyover.FlyoverDeployment memory d = deployer.deployForTesting(
            address(deployer),
            cfg,
            helper.getOptions()
        );
        targets.pegIn = d.pegInProxy;
        targets.pegOut = d.pegOutProxy;
        targets.collateral = d.collateralManagementProxy;
        targets.discovery = d.flyoverDiscoveryProxy;
    }

    function _getHarness() internal view returns (NetworkHarness storage) {
        return _harness;
    }

    function _assertSameOutcome(
        bool referenceOk,
        bytes memory referenceData,
        bool candidateOk,
        bytes memory candidateData,
        string memory message
    ) internal pure {
        require(referenceOk == candidateOk, message);
        if (referenceOk) {
            require(
                keccak256(referenceData) == keccak256(candidateData),
                "Success return data mismatch"
            );
        }
    }

    function _callStatic(
        address target,
        bytes memory callData
    ) internal view returns (bool, bytes memory) {
        return target.staticcall(callData);
    }

    function _callAs(
        address sender,
        address target,
        uint256 value,
        bytes memory callData
    ) internal returns (bool, bytes memory) {
        vm.prank(sender, sender);
        return target.call{value: value}(callData);
    }
}
