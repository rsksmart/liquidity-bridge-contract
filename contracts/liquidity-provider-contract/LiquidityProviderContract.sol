// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/AccessControlDefaultAdminRulesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../libraries/Quotes.sol";
import "../libraries/FlyoverModule.sol";
import "../Bridge.sol";

contract LiquidityProviderContract is Initializable, ReentrancyGuardUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable {

    struct LiquidityProvider {
        uint id;
        address provider;
        string name;
        uint fee;
        uint quoteExpiration;
        uint minTransactionValue;
        uint maxTransactionValue;
        string apiBaseUrl;
        bool status;
        string providerType;
    }

    event Register(uint id, address indexed from, uint256 amount);
    event CollateralIncrease(address from, uint256 amount);
    event PegoutCollateralIncrease(address from, uint256 amount);
    event Withdrawal(address from, uint256 amount);
    event WithdrawCollateral(address from, uint256 amount);
    event PegoutWithdrawCollateral(address from, uint256 amount);
    event Resigned(address from);
    event BalanceIncrease(address dest, uint amount);
    event BalanceDecrease(address dest, uint amount);
    event Penalized(address liquidityProvider, uint penalty, bytes32 quoteHash);
    event BalanceUsed(address module, uint amount);
    event Received(address from, uint amount);
    event Deposited(address liquidityProvider, uint amount);

    Bridge public bridge;

    mapping(address => uint256) private balances;
    mapping(address => uint256) private collateral;
    mapping(address => uint256) private pegoutCollateral;
    mapping(uint => LiquidityProvider) private liquidityProviders;
    mapping(address => uint256) private resignationBlockNum;

    uint256 private minCollateral;
    uint32 private resignDelayInBlocks;
    uint public providerId;
    uint256 private maxQuoteValue;

    modifier onlyOwnerAndProvider(address sender, uint _providerId) {
        require(
            sender == owner() ||
            sender == liquidityProviders[_providerId].provider,
            "LBC005"
        );
        _;
    }

    modifier onlyRegistered(address sender) {
        require(isRegistered(sender), "LBC001");
        _;
    }

    modifier onlyRegisteredForPegout(address sender) {
        require(isRegisteredForPegout(sender), "LBC001");
        _;
    }

    receive() external payable {
        require(msg.sender == address(bridge) || hasRole(FlyoverModule.MODULE_ROLE, msg.sender), "LBC007");
        emit Received(msg.sender, msg.value);
    }

    /**
        @param _bridgeAddress The address of the bridge contract
        @param _minimumCollateral The minimum required collateral for liquidity providers
        @param _resignDelayBlocks The number of block confirmations that a liquidity
        // provider needs to wait before it can withdraw its collateral
        @param _maxQuoteValue Quote value cap
     */
    function initialize(
        address payable _bridgeAddress,
        uint256 _minimumCollateral,
        uint32 _resignDelayBlocks,
        uint _maxQuoteValue
    ) external initializer {
        __AccessControlDefaultAdminRules_init(30 minutes, msg.sender);
        bridge = Bridge(_bridgeAddress);
        minCollateral = _minimumCollateral;
        resignDelayInBlocks = _resignDelayBlocks;
        maxQuoteValue = _maxQuoteValue;
    }

    function getMaxQuoteValue() external view returns (uint256) {
        return maxQuoteValue;
    }

    function getMinCollateral() external view returns (uint) {
        return minCollateral;
    }

    function getResignDelayBlocks() external view returns (uint) {
        return resignDelayInBlocks;
    }

    /**
        @dev Checks if a liquidity provider is registered
        @param addr The address of the liquidity provider
        @return Boolean indicating whether the liquidity provider is registered
     */
    function isRegistered(address addr) public view onlyRole(FlyoverModule.MODULE_ROLE) returns (bool) {
        return collateral[addr] > 0 && resignationBlockNum[addr] == 0;
    }

    function isRegisteredForPegout(address addr) public view onlyRole(FlyoverModule.MODULE_ROLE) returns (bool) {
        return pegoutCollateral[addr] > 0 && resignationBlockNum[addr] == 0;
    }

    /**
        @dev Returns the amount of collateral of a liquidity provider
        @param addr The address of the liquidity provider
        @return The amount of locked collateral
     */
    function getCollateral(address addr) external view returns (uint256) {
        return collateral[addr];
    }

    function getPegoutCollateral(address addr) external view returns (uint256) {
        return pegoutCollateral[addr];
    }

    function setProviderStatus(
        address sender,
        uint _providerId,
        bool status
    ) public onlyRole(FlyoverModule.MODULE_ROLE) onlyOwnerAndProvider(sender, _providerId) {
        liquidityProviders[_providerId].status = status;
    }

    /**
        @dev Registers msg.sender as a liquidity provider with msg.value as collateral
     */
    function register(
        address sender,
        string memory _name,
        uint _fee,
        uint _quoteExpiration,
        uint _minTransactionValue,
        uint _maxTransactionValue,
        string memory _apiBaseUrl,
        bool _status,
        string memory _providerType
    ) external onlyRole(FlyoverModule.MODULE_ROLE) payable returns (uint) {
        //require(collateral[tx.origin] == 0, "Already registered");
        validateRegisterParameters(
            _name,
            _fee,
            _quoteExpiration,
            _minTransactionValue,
            _maxTransactionValue,
            _apiBaseUrl,
            _providerType
        );
        // TODO multiplication by 2 is a temporal fix until we define solution with product team
        require(collateral[sender] == 0 && pegoutCollateral[sender] == 0, "LBC073");
        require(msg.value >= minCollateral * 2, "LBC008");
        require(
            resignationBlockNum[sender] == 0,
            "LBC009"
        );
        // TODO split 50/50 between pegin and pegout is a temporal fix until we define solution with product team
        if (msg.value % 2 == 0) {
            collateral[sender] = msg.value / 2;
            pegoutCollateral[sender] = msg.value / 2;
        } else {
            collateral[sender] = msg.value / 2 + 1;
            pegoutCollateral[sender] = msg.value / 2;
        }

        providerId++;
        liquidityProviders[providerId] = LiquidityProvider({
            id: providerId,
            provider: sender,
            name: _name,
            fee: _fee,
            quoteExpiration: _quoteExpiration,
            minTransactionValue: _minTransactionValue,
            maxTransactionValue: _maxTransactionValue,
            apiBaseUrl: _apiBaseUrl,
            status: _status,
            providerType: _providerType
        });
        emit Register(providerId, sender, msg.value);
        return (providerId);
    }

    /**
        @dev Increases the balance of the sender
     */
    function deposit(address sender) external payable onlyRole(FlyoverModule.MODULE_ROLE) onlyRegistered(sender) {
        balances[sender] += msg.value;
        emit Deposited(sender, msg.value);
    }

    /**
        @dev Increases the amount of collateral of the sender
     */
    function addCollateral(address sender) external payable onlyRole(FlyoverModule.MODULE_ROLE) onlyRegistered(sender) {
        collateral[sender] += msg.value;
        emit CollateralIncrease(sender, msg.value);
    }

    function addPegoutCollateral(address sender)
        external payable onlyRole(FlyoverModule.MODULE_ROLE) onlyRegisteredForPegout(sender) {
        pegoutCollateral[sender] += msg.value;
        emit PegoutCollateralIncrease(sender, msg.value);
    }

    /**
        @dev Checks whether a liquidity provider can deliver a pegin service
        @return Whether the liquidity provider is registered and has enough locked collateral
     */
    function isOperational(address addr) external view returns (bool) {
        return isRegistered(addr) && collateral[addr] >= minCollateral;
    }

    /**
        @dev Checks whether a liquidity provider can deliver a pegout service
        @return Whether the liquidity provider is registered and has enough locked collateral
     */
    function isOperationalForPegout(address addr) external view returns (bool) {
        return
        isRegisteredForPegout(addr) &&
        pegoutCollateral[addr] >= minCollateral;
    }

    /**
        @dev Used to withdraw funds
        @param amount The amount to withdraw
     */
    function withdraw(address sender, uint256 amount) external onlyRole(FlyoverModule.MODULE_ROLE) {
        require(balances[sender] >= amount, "LBC019");
        balances[sender] -= amount;
        (bool success,) = sender.call{value: amount}("");
        require(success, "LBC020");
        emit Withdrawal(sender, amount);
    }

    /**
        @dev Used to withdraw the locked collateral
     */
    function withdrawCollateral(address sender) external onlyRole(FlyoverModule.MODULE_ROLE) {
        require(resignationBlockNum[sender] > 0, "LBC021");
        require(
            block.number - resignationBlockNum[sender] >=
            resignDelayInBlocks,
            "LBC022"
        );
        uint amount = collateral[sender];
        collateral[sender] = 0;
        resignationBlockNum[sender] = 0;
        (bool success,) = sender.call{value: amount}("");
        require(success, "LBC020");
        emit WithdrawCollateral(sender, amount);
    }

    function withdrawPegoutCollateral(address sender) external onlyRole(FlyoverModule.MODULE_ROLE) {
        require(resignationBlockNum[sender] > 0, "LBC021");
        require(
            block.number - resignationBlockNum[sender] >=
            resignDelayInBlocks,
            "LBC022"
        );
        uint amount = pegoutCollateral[sender];
        pegoutCollateral[sender] = 0;
        resignationBlockNum[sender] = 0;
        (bool success,) = sender.call{value: amount}("");
        require(success, "LBC020");
        emit PegoutWithdrawCollateral(sender, amount);
    }

    /**
        @dev Used to resign as a liquidity provider
     */
    function resign(address sender) external onlyRole(FlyoverModule.MODULE_ROLE) onlyRegistered(sender) {
        require(resignationBlockNum[sender] == 0, "LBC023");
        resignationBlockNum[sender] = block.number;
        emit Resigned(sender);
    }

    function getProviderIds() external view returns (uint) {
        return providerId;
    }

    function getProviders(
        uint[] memory providerIds
    ) external view onlyRole(FlyoverModule.MODULE_ROLE) returns (LiquidityProvider[] memory) {
        LiquidityProvider[] memory providersToReturn = new LiquidityProvider[](
            providerIds.length
        );
        uint count = 0;

        for (uint i = 0; i < providerIds.length; i++) {
            uint id = providerIds[i];
            if (
                (isRegistered(liquidityProviders[id].provider) ||
                isRegisteredForPegout(liquidityProviders[id].provider)) &&
                liquidityProviders[id].status
            ) {
                providersToReturn[count] = liquidityProviders[id];
                count++;
            }
        }
        return providersToReturn;
    }

    /**
        @dev Validates input parameters for the register function
    */
    function validateRegisterParameters(
        string memory _name,
        uint _fee,
        uint _quoteExpiration,
        uint _minTransactionValue,
        uint _maxTransactionValue,
        string memory _apiBaseUrl,
        string memory _providerType
    ) internal view {
        require(bytes(_name).length > 0, "LBC010");
        require(_fee > 0, "LBC011");
        require(
            _quoteExpiration > 0,
            "LBC012"
        );
        require(
            _minTransactionValue > 0,
            "LBC014"
        );
        require(
            _maxTransactionValue > _minTransactionValue,
            "LBC015"
        );
        require(_maxTransactionValue <= maxQuoteValue, "LBC016");
        require(
            bytes(_apiBaseUrl).length > 0,
            "LBC017"
        );

        // Check if _providerType is one of the valid strings
        require(
            keccak256(abi.encodePacked(_providerType)) ==
            keccak256(abi.encodePacked("pegin")) ||
            keccak256(abi.encodePacked(_providerType)) ==
            keccak256(abi.encodePacked("pegout")) ||
            keccak256(abi.encodePacked(_providerType)) ==
            keccak256(abi.encodePacked("both")),
            "LBC018"
        );
    }

    // IMPORTANT: These 3 methods should remain restricted to internal modules at all costs
    function increaseBalance(address dest, uint amount) public onlyRole(FlyoverModule.INTERNAL_MODULE_ROLE) {
        balances[dest] += amount;
        emit BalanceIncrease(dest, amount);
    }

    function decreaseBalance(address dest, uint amount) public onlyRole(FlyoverModule.INTERNAL_MODULE_ROLE) {
        balances[dest] -= amount;
        emit BalanceDecrease(dest, amount);
    }

    function useBalance(uint amount) public onlyRole(FlyoverModule.INTERNAL_MODULE_ROLE) nonReentrant {
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "LBC071");
        emit BalanceUsed(msg.sender, amount);
    } 

    function getBalance(address liquidityProvider) public view returns (uint256) {
        return balances[liquidityProvider];
    }

    function penalizeForPegin(Quotes.PeginQuote calldata quote, bytes32 quoteHash)
        public onlyRole(FlyoverModule.INTERNAL_MODULE_ROLE) returns (uint) {
        uint currentColalteral = collateral[quote.liquidityProviderRskAddress];
        // prevent underflow when collateral is less than penalty fee.
        uint penalizationAmount = quote.penaltyFee < currentColalteral ? quote.penaltyFee : currentColalteral;
        collateral[quote.liquidityProviderRskAddress] -= penalizationAmount;
        emit Penalized(quote.liquidityProviderRskAddress, penalizationAmount, quoteHash);
        return penalizationAmount;
    }

    function penalizeForPegout(Quotes.PegOutQuote calldata quote, bytes32 quoteHash)
        public onlyRole(FlyoverModule.INTERNAL_MODULE_ROLE) returns (uint) {
        uint currentColalteral = pegoutCollateral[quote.lpRskAddress];
        uint penalty = quote.penaltyFee < currentColalteral ? quote.penaltyFee : currentColalteral;
        pegoutCollateral[quote.lpRskAddress] -= penalty;
        emit Penalized(quote.lpRskAddress, penalty, quoteHash);
        return penalty;
    }
}