// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {LendingPool} from "./LendingPool.sol";

/// @title LendingPoolManager - Factory contract for creating and managing lending pools
/// @notice Manages the creation and retrieval of lending pools with different parameters
/// @dev Implements access control and prevents reentrancy attacks
contract LendingPoolManager is Ownable, ReentrancyGuard {

    /// @notice Thrown when attempting to create a lending pool that already exists
    /// @dev Identified by the unique key generated from debt token, collateral token, maturity month and year
    error LendingPoolAlreadyExists();

    /// @notice Thrown when attempting to retrieve a non-existent lending pool
    error LendingPoolNotFound();

    /// @notice Emitted when a new lending pool is created
    /// @param lendingPool The address of the created lending pool
    /// @param creator The address that created the pool
    /// @param info The configuration parameters of the created pool
    event LendingPoolCreated(address lendingPool, address indexed creator, LendingPool.LendingPoolInfo info);

    /// @notice Mapping from pool key to LendingPool contract
    /// @dev Key is generated from debt token, collateral token, maturity month and year
    mapping(bytes32 => LendingPool) public lendingPools;

    /// @notice Initializes the contract with the deployer as owner
    constructor() Ownable(msg.sender) {}

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
        return keccak256(abi.encodePacked(debtToken_, collateralToken_, maturityMonth_, maturityYear_));
    }

    /// @notice Creates a new lending pool with specified parameters
    /// @dev Only callable by owner, implements reentrancy protection
    /// @param debtToken_ The token that can be borrowed from the pool
    /// @param collateralToken_ The token that can be used as collateral
    /// @param oracle_ The price oracle for the collateral token
    /// @param maturity_ The timestamp when the pool matures
    /// @param maturityMonth_ The month when the pool matures (e.g., "MAY")
    /// @param maturityYear_ The year when the pool matures
    /// @param ltv_ The loan-to-value ratio in 1e18 format (e.g., 75% = 75e16)
    function createLendingPool(
        address debtToken_,
        address collateralToken_,
        address oracle_,
        uint256 maturity_,
        string memory maturityMonth_,
        uint256 maturityYear_,
        uint256 ltv_
    ) external onlyOwner nonReentrant {
        bytes32 key = _generateLendingPoolKey(debtToken_, collateralToken_, maturityMonth_, maturityYear_);
        if (address(lendingPools[key]) != address(0)) revert LendingPoolAlreadyExists();
        LendingPool.LendingPoolInfo memory info = LendingPool.LendingPoolInfo({
            debtToken: debtToken_,
            collateralToken: collateralToken_,
            oracle: oracle_,
            maturity: maturity_,
            maturityMonth: maturityMonth_,
            maturityYear: maturityYear_,
            ltv: ltv_
        });
        lendingPools[key] = new LendingPool(msg.sender, info);

        emit LendingPoolCreated(address(lendingPools[key]), msg.sender, info);
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
        bytes32 key = _generateLendingPoolKey(debtToken_, collateralToken_, maturityMonth_, maturityYear_);
        if (address(lendingPools[key]) == address(0)) revert LendingPoolNotFound();
        return address(lendingPools[key]);
    }
}