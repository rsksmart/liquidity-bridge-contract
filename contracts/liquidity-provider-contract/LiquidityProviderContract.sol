// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../libraries/Quotes.sol";
import "../Bridge.sol";

contract LiquidityProviderContract is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {

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

    modifier onlyOwnerAndProvider(uint _providerId) {
        require(
            tx.origin == owner() ||
            tx.origin == liquidityProviders[_providerId].provider,
            "LBC005"
        );
        _;
    }

    modifier onlyRegistered() {
        require(isRegistered(tx.origin), "LBC001");
        _;
    }

    modifier onlyRegisteredForPegout() {
        require(isRegisteredForPegout(tx.origin), "LBC001");
        _;
    }

    receive() external payable {
        // TODO only callable from module or bridge
        // require(msg.sender == address(bridge), "LBC007");
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
        __Ownable_init_unchained();
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
    function isRegistered(address addr) public view returns (bool) { // TODO CHECK SECURITY OR RETURN TO PRIVATE
        return collateral[addr] > 0 && resignationBlockNum[addr] == 0;
    }

    // TODO CHECK SECURITY OR RETURN TO PRIVATE
    function isRegisteredForPegout(address addr) public view returns (bool) {
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
        uint _providerId,
        bool status
    ) public onlyOwnerAndProvider(_providerId) {
        liquidityProviders[_providerId].status = status;
    }

    /**
        @dev Registers tx.origin as a liquidity provider with msg.value as collateral
     */
    function register(
        string memory _name,
        uint _fee,
        uint _quoteExpiration,
        uint _minTransactionValue,
        uint _maxTransactionValue,
        string memory _apiBaseUrl,
        bool _status,
        string memory _providerType
    ) external payable returns (uint) {
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
        require(msg.value >= minCollateral * 2, "LBC008");
        require(
            resignationBlockNum[tx.origin] == 0,
            "LBC009"
        );
        // TODO split 50/50 between pegin and pegout is a temporal fix until we define solution with product team
        if (msg.value % 2 == 0) {
            collateral[tx.origin] = msg.value / 2;
            pegoutCollateral[tx.origin] = msg.value / 2;
        } else {
            collateral[tx.origin] = msg.value / 2 + 1;
            pegoutCollateral[tx.origin] = msg.value / 2;
        }

        providerId++;
        liquidityProviders[providerId] = LiquidityProvider({
            id: providerId,
            provider: tx.origin,
            name: _name,
            fee: _fee,
            quoteExpiration: _quoteExpiration,
            minTransactionValue: _minTransactionValue,
            maxTransactionValue: _maxTransactionValue,
            apiBaseUrl: _apiBaseUrl,
            status: _status,
            providerType: _providerType
        });
        emit Register(providerId, tx.origin, msg.value);
        return (providerId);
    }

    /**
        @dev Increases the balance of the sender
     */
    function deposit() external payable onlyRegistered {
        increaseBalance(tx.origin, msg.value);
    }

    /**
        @dev Increases the amount of collateral of the sender
     */
    function addCollateral() external payable onlyRegistered {
        collateral[tx.origin] += msg.value;
        emit CollateralIncrease(tx.origin, msg.value);
    }

    function addPegoutCollateral() external payable onlyRegisteredForPegout {
        pegoutCollateral[tx.origin] += msg.value;
        emit PegoutCollateralIncrease(tx.origin, msg.value);
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
    function withdraw(uint256 amount) external {
        require(balances[tx.origin] >= amount, "LBC019");
        balances[tx.origin] -= amount;
        (bool success,) = tx.origin.call{value: amount}("");
        require(success, "LBC020");
        emit Withdrawal(tx.origin, amount);
    }

    /**
        @dev Used to withdraw the locked collateral
     */
    function withdrawCollateral() external {
        require(resignationBlockNum[tx.origin] > 0, "LBC021");
        require(
            block.number - resignationBlockNum[tx.origin] >=
            resignDelayInBlocks,
            "LBC022"
        );
        uint amount = collateral[tx.origin];
        collateral[tx.origin] = 0;
        resignationBlockNum[tx.origin] = 0;
        (bool success,) = tx.origin.call{value: amount}("");
        require(success, "LBC020");
        emit WithdrawCollateral(tx.origin, amount);
    }

    function withdrawPegoutCollateral() external {
        require(resignationBlockNum[tx.origin] > 0, "LBC021");
        require(
            block.number - resignationBlockNum[tx.origin] >=
            resignDelayInBlocks,
            "LBC022"
        );
        uint amount = pegoutCollateral[tx.origin];
        pegoutCollateral[tx.origin] = 0;
        resignationBlockNum[tx.origin] = 0;
        (bool success,) = tx.origin.call{value: amount}("");
        require(success, "LBC020");
        emit PegoutWithdrawCollateral(tx.origin, amount);
    }

    /**
        @dev Used to resign as a liquidity provider
     */
    function resign() external onlyRegistered {
        require(resignationBlockNum[tx.origin] == 0, "LBC023");
        resignationBlockNum[tx.origin] = block.number;
        emit Resigned(tx.origin);
    }

    function getProviderIds() external view returns (uint) {
        return providerId;
    }

    function getProviders(
        uint[] memory providerIds
    ) external view returns (LiquidityProvider[] memory) {
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

        // IMPORTANT: These methods should remain private at all costs
    function increaseBalance(address dest, uint amount) public { // TODO FIX SECURITY OR RETURN TO PRIVATE 
        balances[dest] += amount;
        emit BalanceIncrease(dest, amount);
    }

    function decreaseBalance(address dest, uint amount) public { // TODO FIX SECURITY OR RETURN TO PRIVATE
        balances[dest] -= amount;
        emit BalanceDecrease(dest, amount);
    }

    function useBalance(uint amount) nonReentrant public { // TODO FIX SECURITY OR RETURN TO PRIVATE
        // TODO SENDER MUST BE FLYOVER MODULE
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "LBC071");
        emit BalanceUsed(msg.sender, amount);
    } 

    function getBalance(address liquidityProvider) public view returns (uint256) {
        return balances[liquidityProvider];
    }

    // TODO FIX SECURITY OR RETURN TO PRIVATE
    function penalizeForPegin(Quotes.PeginQuote calldata quote, bytes32 quoteHash) public returns (uint) {
        uint currentColalteral = collateral[quote.liquidityProviderRskAddress];
        // prevent underflow when collateral is less than penalty fee.
        uint penalizationAmount = quote.penaltyFee < currentColalteral ? quote.penaltyFee : currentColalteral;
        collateral[quote.liquidityProviderRskAddress] -= penalizationAmount;
        emit Penalized(quote.liquidityProviderRskAddress, penalizationAmount, quoteHash);
        return penalizationAmount;
    }

    // TODO FIX SECURITY OR RETURN TO PRIVATE
    function penalizeForPegout(Quotes.PegOutQuote calldata quote, bytes32 quoteHash) public returns (uint) {
        uint currentColalteral = pegoutCollateral[quote.lpRskAddress];
        uint penalty = quote.penaltyFee < currentColalteral ? quote.penaltyFee : currentColalteral;
        pegoutCollateral[quote.lpRskAddress] -= penalty;
        emit Penalized(quote.lpRskAddress, penalty, quoteHash);
        return penalty;
    }
}