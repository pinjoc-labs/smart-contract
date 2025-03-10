// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {LendingPool} from "../LendingPool.sol";

/// @title ILendingPoolManager - Interface for managing lending pools
/// @notice Manages the creation and retrieval of lending pools with different parameters
/// @dev Implements access control and prevents reentrancy attacks
interface ILendingPoolManager {
    /// @notice Thrown when attempting to set an invalid router address
    error InvalidRouter();

    /// @notice Thrown when the caller is not the router
    error OnlyRouter();

    /// @notice Thrown when attempting to create a lending pool with invalid parameters
    error InvalidCreateLendingPoolParameter();

    /// @notice Thrown when attempting to create a lending pool that already exists
    /// @dev Identified by the unique key generated from debt token, collateral token, maturity month and year
    error LendingPoolAlreadyExists();
    
    /// @notice Thrown when attempting to set an invalid oracle address
    error InvalidOracle();

    /// @notice Thrown when attempting to set an oracle for a lending pool that doesn't exist
    error OracleNotFound();

    /// @notice Emitted when a new lending pool is created
    /// @param lendingPool The address of the created lending pool
    /// @param owner The address of the owner of the pool
    /// @param creator The address that created the pool
    /// @param info The configuration parameters of the created pool
    event LendingPoolCreated(
        address lendingPool,
        address owner,
        address indexed creator,
        LendingPool.LendingPoolInfo info
    );

    /// @notice Emitted when the router address is set
    /// @param router The address of the router
    event RouterSet(address indexed router);

    /// @notice Emitted when an oracle is set for a lending pool
    /// @param oracle The address of the oracle
    /// @param debtToken The token that can be borrowed from the pool
    /// @param collateralToken The token that can be used as collateral
    event OracleSet(address indexed oracle, address indexed debtToken, address indexed collateralToken);

    /// @notice Sets the router address
    /// @dev Only callable by owner
    /// @param router_ The address of the router
    function setRouter(address router_) external;

    /// @notice Sets the oracle for a lending pool
    /// @dev Only callable by owner, implements reentrancy protection
    /// @param oracle_ The address of the oracle
    /// @param debtToken_ The token that can be borrowed from the pool
    /// @param collateralToken_ The token that can be used as collateral
    function setOracle(address oracle_, address debtToken_, address collateralToken_) external;

    /// @notice Retrieves the address of an oracle based on its parameters  
    /// @dev Reverts if the oracle doesn't exist
    /// @param debtToken_ The token that can be borrowed from the pool
    /// @param collateralToken_ The token that can be used as collateral
    /// @return The address of the oracle
    function getOracle(address debtToken_, address collateralToken_) external view returns (address);

    /// @notice Creates a new lending pool with specified parameters
    /// @dev Only callable by owner, implements reentrancy protection
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
    ) external returns (address);

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
    ) external view returns (address);
}
