// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {IPegInAddressRegistry} from "../../src/interfaces/IPegInAddressRegistry.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

contract PegInAddressRegistryTest is Test {
    address constant USER_1 =
        address(0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56);
    address constant USER_2 =
        address(0x129d2280f9C35C0Caf3f172d487Fd9A3f894fD26);
    address constant ZERO_ADDRESS = address(0);

    address owner = address(1);
    address watchtower = address(2);
    PegInAddressRegistry internal _registry;
    BridgeMock internal _bridge;
    PauseRegistry internal _pauseRegistry;

    function setUp() public {
        PauseRegistry prImpl = new PauseRegistry();
        ERC1967Proxy prProxy = new ERC1967Proxy(
            address(prImpl),
            abi.encodeCall(prImpl.initialize, (uint48(0), owner))
        );
        _pauseRegistry = PauseRegistry(payable(address(prProxy)));

        _bridge = new BridgeMock();

        PegInAddressRegistry implementation = new PegInAddressRegistry();
        bytes memory initData = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, payable(address(_bridge)), false, address(_pauseRegistry))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        _registry = PegInAddressRegistry(address(proxy));
    }

    function test_Initialize_SetsPauseRegistry() public view {
        assertEq(address(_registry.pauseRegistry()), address(_pauseRegistry));
    }

    function test_Initialize_RevertsIfPauseRegistryHasNoCode() public {
        PegInAddressRegistry implementation = new PegInAddressRegistry();
        bytes memory initDataZero = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, payable(address(_bridge)), false, ZERO_ADDRESS)
        );

        vm.expectRevert(
            abi.encodeWithSelector(Flyover.NoContract.selector, ZERO_ADDRESS)
        );
        new ERC1967Proxy(address(implementation), initDataZero);

        address eoa = makeAddr("eoa");
        PegInAddressRegistry implementation2 = new PegInAddressRegistry();
        bytes memory initDataEoa = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, payable(address(_bridge)), false, eoa)
        );

        vm.expectRevert(
            abi.encodeWithSelector(Flyover.NoContract.selector, eoa)
        );
        new ERC1967Proxy(address(implementation2), initDataEoa);
    }

    function test_RegisterAddress_StoresStateAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IPegInAddressRegistry.AddressRegistered(
            USER_1,
            address(this),
            keccak256(abi.encodePacked(bytes32(0), USER_1))
        );

        _registry.registerAddress(USER_1);

        assertTrue(_registry.isRegistered(USER_1));
        assertEq(_registry.getRegistrationBlock(USER_1), block.number);
        assertEq(_registry.getRegistrant(USER_1), address(this));
        assertEq(_registry.getRegistrationCount(), 1);
        assertEq(
            _registry.getRegistrationRoot(),
            keccak256(abi.encodePacked(bytes32(0), USER_1))
        );
    }

    function test_RegisterAddress_StoresRegistrant() public {
        vm.prank(watchtower);
        _registry.registerAddress(USER_1);

        assertEq(_registry.getRegistrant(USER_1), watchtower);
    }

    function test_GetRegistrant_ReturnsZeroForUnregisteredAddress()
        public
        view
    {
        assertEq(_registry.getRegistrant(USER_1), address(0));
    }

    function test_RegisterAddress_RevertsOnZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.InvalidAddress.selector, address(0))
        );
        _registry.registerAddress(address(0));
    }

    function test_RegisterAddress_RevertsWhenAlreadyRegistered() public {
        _registry.registerAddress(USER_1);

        vm.expectRevert(
            abi.encodeWithSelector(
                PegInAddressRegistry.AlreadyRegistered.selector,
                USER_1
            )
        );
        _registry.registerAddress(USER_1);
    }

    function test_RegisterAddress_UpdatesRegistrationRootInOrder() public {
        _registry.registerAddress(USER_1);

        bytes32 expectedRoot = keccak256(
            abi.encodePacked(_registry.getRegistrationRoot(), USER_2)
        );
        _registry.registerAddress(USER_2);

        assertEq(_registry.getRegistrationCount(), 2);
        assertEq(_registry.getRegistrationRoot(), expectedRoot);
        assertTrue(_registry.isRegistered(USER_2));
    }

    function test_GetPegInAddress_IsDeterministic() public {
        (
            bytes memory address1,
            IPegInAddressRegistry.Encoding encoding1
        ) = _registry.getPegInAddress(USER_1);
        (
            bytes memory address2,
            IPegInAddressRegistry.Encoding encoding2
        ) = _registry.getPegInAddress(USER_1);

        assertEq(keccak256(address1), keccak256(address2));
        assertEq(
            uint8(encoding1),
            uint8(IPegInAddressRegistry.Encoding.BASE58)
        );
        assertEq(
            uint8(encoding2),
            uint8(IPegInAddressRegistry.Encoding.BASE58)
        );
        assertEq(address1.length, 25);
    }

    function test_GetPegInAddress_DoesNotRequireRegistration() public {
        assertFalse(_registry.isRegistered(USER_1));
        (bytes memory derivationAddress, ) = _registry.getPegInAddress(USER_1);
        assertEq(derivationAddress.length, 25);
    }

    function test_GetPegInAddresses_ReturnsBatchDerivations() public {
        address[] memory addrs = new address[](2);
        addrs[0] = USER_1;
        addrs[1] = USER_2;

        (
            bytes[] memory batch,
            IPegInAddressRegistry.Encoding encoding
        ) = _registry.getPegInAddresses(addrs);
        (bytes memory single1, ) = _registry.getPegInAddress(USER_1);
        (bytes memory single2, ) = _registry.getPegInAddress(USER_2);

        assertEq(batch.length, 2);
        assertEq(keccak256(batch[0]), keccak256(single1));
        assertEq(keccak256(batch[1]), keccak256(single2));
        assertEq(uint8(encoding), uint8(IPegInAddressRegistry.Encoding.BASE58));
    }

    function test_RegisterAddress_RevertsWhenSoftPaused() public {
        vm.prank(owner);
        _pauseRegistry.setPauseLevel(IPauseRegistry.PauseLevel.Soft, "test");

        vm.expectRevert(Flyover.EnforcedPause.selector);
        _registry.registerAddress(USER_1);
    }
}
