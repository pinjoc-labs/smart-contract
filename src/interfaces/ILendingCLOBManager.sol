// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title ILendingCLOBManager - Interface for managing lending CLOB
/// @notice Manages the creation and retrieval of lending CLOB with different parameters
/// @dev Implements access control and prevents reentrancy attacks
interface ILendingCLOBManager {
    /// @notice Thrown when attempting to create a lending CLOB that already exists
    /// @dev Identified by the unique key generated from debt token, collateral token, maturity month and year
    error LendingCLOBAlreadyExists();

    /// @notice Emitted when a new lending CLOB is created
    /// @param lendingCLOB The address of the created lending CLOB
    /// @param creator The address that created the CLOB
    /// @param debtToken The address of the debt token
    /// @param collateralToken The address of the collateral token
    /// @param maturityMonth The month when the CLOB matures
    /// @param maturityYear The year when the CLOB matures
    event LendingCLOBCreated(
        address lendingCLOB,
        address indexed creator,
        address debtToken,
        address collateralToken,
        string maturityMonth,
        uint256 maturityYear
    );

    /// @notice Creates a new lending CLOB with specified parameters
    /// @dev Only callable by owner, implements reentrancy protection
    /// @param debtToken_ The token that can be borrowed from the CLOB
    /// @param collateralToken_ The token that can be used as collateral
    /// @param maturityMonth_ The month when the CLOB matures (e.g., "MAY")
    /// @param maturityYear_ The year when the CLOB matures
    function createLendingCLOB(
        address debtToken_,
        address collateralToken_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) external returns (address);

    /// @notice Retrieves the address of a lending CLOB based on its parameters
    /// @dev Reverts if the CLOB doesn't exist
    /// @param debtToken_ The debt token of the CLOB
    /// @param collateralToken_ The collateral token of the CLOB
    /// @param maturityMonth_ The maturity month of the CLOB
    /// @param maturityYear_ The maturity year of the CLOB
    /// @return The address of the lending CLOB
    function getLendingCLOB(
        address debtToken_,
        address collateralToken_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) external view returns (address);
}
