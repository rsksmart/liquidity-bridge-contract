// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {AddressResolver} from "../helpers/AddressResolver.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";

/**
 * @title QueryFlyoverRoles
 * @notice Read-only script: Flyover role layout and which scanned addresses hold each role
 * @dev OpenZeppelin `AccessControl` does not expose role member enumeration on-chain. This script
 *      prints role ids, admins, default-admin state, then **only addresses that have the role**
 *      from the scan set: each contract's `defaultAdmin()`, plus optional
 *      `ROLE_QUERY_CHECK_ADDRESSES` (comma-separated).
 *
 * ## Usage
 *   forge script script/tasks/QueryFlyoverRoles.s.sol:QueryFlyoverRoles \
 *     --sig "queryRoles()" \
 *     --rpc-url <rpc-url>
 *
 * Optional (comma-separated checks, e.g. multisig + ops):
 *   ROLE_QUERY_CHECK_ADDRESSES="0xabc...,0xdef..." forge script ... --sig "queryRoles()" --rpc-url ...
 *
 * ## Environment (same resolution as AddressResolver.sol)
 * - PAUSE_REGISTRY_ADDRESS, PEGIN_CONTRACT_ADDRESS, PEGOUT_CONTRACT_ADDRESS,
 *   COLLATERAL_MANAGEMENT_ADDRESS, FLYOVER_DISCOVERY_ADDRESS
 *   or entries in addresses.json with NETWORK (default rskRegtest)
 */

/// @dev PauseRegistry public role constant
interface IPauseRegistryRoles {
    function PAUSER_ROLE() external view returns (bytes32);
}

/// @dev CollateralManagementContract public role constants
interface ICollateralManagementRoles {
    function COLLATERAL_ADDER() external view returns (bytes32);

    function COLLATERAL_SLASHER() external view returns (bytes32);
}

contract QueryFlyoverRoles is Script, AddressResolver {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    uint256 internal constant MAX_CHECK_ADDRS = 48;

    function queryRoles() public view {
        console.log("\n=== FLYOVER ACCESS CONTROL ROLES ===\n");

        address pauseReg = getPauseRegistryAddress();
        address pegIn = getPegInAddress();
        address pegOut = getPegOutAddress();
        address collateral = getCollateralManagementAddress();
        address discovery = getFlyoverDiscoveryAddress();

        address[] memory checkAddrs = _collectCheckAddresses(
            pauseReg,
            pegIn,
            pegOut,
            collateral,
            discovery
        );

        _printContractBlock("PauseRegistry", pauseReg, checkAddrs);
        _printRoleLine(
            pauseReg,
            "DEFAULT_ADMIN_ROLE",
            DEFAULT_ADMIN_ROLE,
            checkAddrs
        );
        _printRoleLine(
            pauseReg,
            "PAUSER_ROLE",
            IPauseRegistryRoles(pauseReg).PAUSER_ROLE(),
            checkAddrs
        );

        _printContractBlock("PegInContract", pegIn, checkAddrs);
        _printRoleLine(
            pegIn,
            "DEFAULT_ADMIN_ROLE",
            DEFAULT_ADMIN_ROLE,
            checkAddrs
        );

        _printContractBlock("PegOutContract", pegOut, checkAddrs);
        _printRoleLine(
            pegOut,
            "DEFAULT_ADMIN_ROLE",
            DEFAULT_ADMIN_ROLE,
            checkAddrs
        );

        _printContractBlock("CollateralManagement", collateral, checkAddrs);
        _printRoleLine(
            collateral,
            "DEFAULT_ADMIN_ROLE",
            DEFAULT_ADMIN_ROLE,
            checkAddrs
        );
        _printRoleLine(
            collateral,
            "COLLATERAL_ADDER",
            ICollateralManagementRoles(collateral).COLLATERAL_ADDER(),
            checkAddrs
        );
        _printRoleLine(
            collateral,
            "COLLATERAL_SLASHER",
            ICollateralManagementRoles(collateral).COLLATERAL_SLASHER(),
            checkAddrs
        );

        _printContractBlock("FlyoverDiscovery", discovery, checkAddrs);
        _printRoleLine(
            discovery,
            "DEFAULT_ADMIN_ROLE",
            DEFAULT_ADMIN_ROLE,
            checkAddrs
        );
        console.log("====================================\n");
    }

    function run() external view {
        queryRoles();
    }

    function _collectCheckAddresses(
        address pauseReg,
        address pegIn,
        address pegOut,
        address collateral,
        address discovery
    ) internal view returns (address[] memory) {
        address[MAX_CHECK_ADDRS] memory buf;
        uint256 n = 0;

        n = _pushUnique(
            buf,
            n,
            IAccessControlDefaultAdminRules(pauseReg).defaultAdmin()
        );
        n = _pushUnique(
            buf,
            n,
            IAccessControlDefaultAdminRules(pegIn).defaultAdmin()
        );
        n = _pushUnique(
            buf,
            n,
            IAccessControlDefaultAdminRules(pegOut).defaultAdmin()
        );
        n = _pushUnique(
            buf,
            n,
            IAccessControlDefaultAdminRules(collateral).defaultAdmin()
        );
        n = _pushUnique(
            buf,
            n,
            IAccessControlDefaultAdminRules(discovery).defaultAdmin()
        );

        string memory extra = vm.envOr(
            "ROLE_QUERY_CHECK_ADDRESSES",
            string("")
        );
        if (bytes(extra).length != 0) {
            string[] memory parts = vm.split(extra, ",");
            for (uint256 i = 0; i < parts.length; i++) {
                if (n >= MAX_CHECK_ADDRS) break;
                string memory t = vm.trim(parts[i]);
                if (bytes(t).length == 0) continue;
                address a = vm.parseAddress(t);
                n = _pushUnique(buf, n, a);
            }
        }

        address[] memory out = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            out[i] = buf[i];
        }
        return out;
    }

    function _pushUnique(
        address[MAX_CHECK_ADDRS] memory buf,
        uint256 n,
        address a
    ) internal pure returns (uint256) {
        if (a == address(0)) return n;
        for (uint256 i = 0; i < n; i++) {
            if (buf[i] == a) return n;
        }
        require(
            n < MAX_CHECK_ADDRS,
            "QueryFlyoverRoles: too many check addresses"
        );
        buf[n] = a;
        return n + 1;
    }

    function _printContractBlock(
        string memory title,
        address c,
        address[] memory checkAddrs
    ) internal view {
        console.log(
            string.concat("--- ", title, " @ ", vm.toString(c), " ---")
        );
        IAccessControlDefaultAdminRules ac = IAccessControlDefaultAdminRules(c);
        address admin = ac.defaultAdmin();
        console.log(string.concat("  defaultAdmin(): ", vm.toString(admin)));

        (address pendingAdmin, uint48 acceptSchedule) = ac
            .pendingDefaultAdmin();
        if (acceptSchedule != 0 || pendingAdmin != address(0)) {
            console.log(
                string.concat(
                    "  pendingDefaultAdmin: ",
                    vm.toString(pendingAdmin),
                    " acceptSchedule: ",
                    vm.toString(uint256(acceptSchedule))
                )
            );
        }

        console.log(
            string.concat(
                "  scan set: ",
                vm.toString(checkAddrs.length),
                " address(es) (defaultAdmins + ROLE_QUERY_CHECK_ADDRESSES)"
            )
        );
        console.log("");
    }

    function _printRoleLine(
        address c,
        string memory roleName,
        bytes32 role,
        address[] memory checkAddrs
    ) internal view {
        IAccessControl ac = IAccessControl(c);
        bytes32 adminRole = ac.getRoleAdmin(role);
        console.log(string.concat("  Role: ", roleName));
        console.log(string.concat("    id: ", vm.toString(role)));
        console.log(
            string.concat("    getRoleAdmin: ", vm.toString(adminRole))
        );

        for (uint256 i = 0; i < checkAddrs.length; i++) {
            address a = checkAddrs[i];
            if (ac.hasRole(role, a)) {
                console.log(string.concat("    ", vm.toString(a)));
            }
        }
        console.log("");
    }
}
