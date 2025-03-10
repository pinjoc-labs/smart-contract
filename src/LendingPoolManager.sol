// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ILendingPoolManager} from "./interfaces/ILendingPoolManager.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {LendingPool} from "./LendingPool.sol";

/// @title LendingPoolManager - Factory contract for creating and managing lending pools
/// @notice Manages the creation and retrieval of lending pools with different parameters
/// @dev Implements access control and prevents reentrancy attacks
contract LendingPoolManager is ILendingPoolManager, Ownable, ReentrancyGuard {
    /// @notice Address of the lending router
    address public router;

    /// @notice Mapping from pool key to LendingPool contract
    /// @dev Key is generated from debt token, collateral token, maturity month and year
    mapping(bytes32 => address) public lendingPools;

    /// @notice Mapping from oracle key to oracle address
    /// @dev Key is generated from debt token and collateral token
    mapping(bytes32 => address) public oracles;

    /// @notice Modifier to ensure the caller is the router
    modifier onlyRouter() {
        if (msg.sender != router) revert OnlyRouter();
        _;
    }

    /// @notice Initializes the contract with the deployer as owner
    constructor(address router_) Ownable(msg.sender) {
        setRouter(router_);
    }

    /// @notice Sets the router address
    /// @dev Only callable by owner
    /// @param router_ The address of the router
    function setRouter(address router_) public onlyOwner {
        if (router_ == address(0)) revert InvalidRouter();
        router = router_;
        emit RouterSet(router_);
    }

    /// @notice Generates a unique key for a lending pool based on its parameters
    /// @dev Uses keccak256 hash of concatenated parameters
    /// @param debtToken_ The token that can be borrowed from the pool
    /// @param collateralToken_ The token that can be used as collateral
    /// @param maturityMonth_ The month when the pool matures (e.g., "MAY")
    /// @param maturityYear_ The year when the pool matures
    /// @return The unique key for the lending pool
    function _generateLendingPoolKey(
        address debtToken_,
        address collateralToken_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    debtToken_,
                    collateralToken_,
                    maturityMonth_,
                    maturityYear_
                )
            );
    }

    /// @notice Generates a unique key for an oracle based on its parameters
    /// @dev Uses keccak256 hash of concatenated parameters
    /// @param debtToken_ The token that can be borrowed from the pool
    /// @param collateralToken_ The token that can be used as collateral
    /// @return The unique key for the oracle
    function _generateOracleKey(address debtToken_, address collateralToken_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(debtToken_, collateralToken_));
    }

    /// @notice Sets the oracle for a lending pool
    /// @dev Only callable by owner, implements reentrancy protection
    /// @param oracle_ The address of the oracle
    /// @param debtToken_ The token that can be borrowed from the pool
    /// @param collateralToken_ The token that can be used as collateral
    function setOracle(address oracle_, address debtToken_, address collateralToken_) external onlyOwner {
        if (oracle_ == address(0)) revert InvalidOracle();
        bytes32 key = _generateOracleKey(debtToken_, collateralToken_);
        oracles[key] = oracle_;
        emit OracleSet(oracle_, debtToken_, collateralToken_);
    }

    /// @notice Retrieves the address of an oracle based on its parameters  
    /// @dev Reverts if the oracle doesn't exist
    /// @param debtToken_ The token that can be borrowed from the pool
    /// @param collateralToken_ The token that can be used as collateral
    /// @return The address of the oracle
    function getOracle(address debtToken_, address collateralToken_) external view returns (address) {
        bytes32 key = _generateOracleKey(debtToken_, collateralToken_);
        if (oracles[key] == address(0)) revert OracleNotFound();
        return oracles[key];
    }

    /// @notice Creates a new lending pool with specified parameters
    /// @dev Only callable by router, implements reentrancy protection
    /// @param debtToken_ The token that can be borrowed from the pool
    /// @param collateralToken_ The token that can be used as collateral
    /// @param maturity_ The timestamp when the pool matures
    /// @param maturityMonth_ The month when the pool matures (e.g., "MAY")
    /// @param maturityYear_ The year when the pool matures
    /// @return The address of the created lending pool
    function createLendingPool(
        address debtToken_,
        address collateralToken_,
        uint256 maturity_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) external onlyRouter nonReentrant returns (address) {
        if (
            debtToken_ == address(0) ||
            collateralToken_ == address(0) ||
            maturity_ == 0 ||
            bytes(maturityMonth_).length == 0 ||
            maturityYear_ == 0
        ) revert InvalidCreateLendingPoolParameter();

        bytes32 oracleKey = _generateOracleKey(debtToken_, collateralToken_);
        if (oracles[oracleKey] == address(0)) revert OracleNotFound();

        bytes32 lendingPoolKey = _generateLendingPoolKey(
            debtToken_,
            collateralToken_,
            maturityMonth_,
            maturityYear_
        );
        if (lendingPools[lendingPoolKey] != address(0)) revert LendingPoolAlreadyExists();
        
        ILendingPool.LendingPoolInfo memory info = ILendingPool
            .LendingPoolInfo({
                debtToken: debtToken_,
                collateralToken: collateralToken_,
                oracle: oracles[oracleKey],
                maturity: maturity_,
                maturityMonth: maturityMonth_,
                maturityYear: maturityYear_,
                ltv: 90e16
            });
        // msg.sender is the router
        lendingPools[lendingPoolKey] = address(new LendingPool(owner(), msg.sender, info));
        emit LendingPoolCreated(lendingPools[lendingPoolKey], owner(), msg.sender, info);

        return lendingPools[lendingPoolKey];
    }

    /// @notice Retrieves the address of a lending pool based on its parameters
    /// @dev Reverts if the pool doesn't exist
    /// @param debtToken_ The debt token of the pool
    /// @param collateralToken_ The collateral token of the pool
    /// @param maturityMonth_ The maturity month of the pool
    /// @param maturityYear_ The maturity year of the pool
    /// @return The address of the lending pool
    function getLendingPool(
        address debtToken_,
        address collateralToken_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) external view returns (address) {
        bytes32 key = _generateLendingPoolKey(
            debtToken_,
            collateralToken_,
            maturityMonth_,
            maturityYear_
        );
        if (lendingPools[key] == address(0)) revert LendingPoolNotFound();
        return lendingPools[key];
    }
}
