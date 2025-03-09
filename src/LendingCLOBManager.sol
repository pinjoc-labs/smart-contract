// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {LendingCLOB} from "./LendingCLOB.sol";

/// @title LendingCLOBManager - Factory contract for creating and managing lending CLOB
/// @notice Manages the creation and retrieval of lending CLOB with different parameters
/// @dev Implements access control and prevents reentrancy attacks
contract LendingCLOBManager is Ownable, ReentrancyGuard {

    /// @notice Thrown when attempting to create a lending CLOB that already exists
    /// @dev Identified by the unique key generated from debt token, collateral token, maturity month and year
    error LendingCLOBAlreadyExists();

    /// @notice Thrown when attempting to retrieve a non-existent lending CLOB
    error LendingCLOBNotFound();

    /// @notice Emitted when a new lending CLOB is created
    /// @param lendingCLOB The address of the created lending CLOB
    /// @param creator The address that created the CLOB
    /// @param debtToken The address of the debt token
    /// @param collateralToken The address of the collateral token
    /// @param maturityMonth The month when the CLOB matures
    /// @param maturityYear The year when the CLOB matures
    event LendingCLOBCreated(address lendingCLOB, address indexed creator, address debtToken, address collateralToken, string maturityMonth, uint256 maturityYear);

    /// @notice Mapping from CLOB key to LendingCLOB contract
    /// @dev Key is generated from debt token, collateral token, maturity month and year
    mapping(bytes32 => LendingCLOB) public lendingCLOB;

    /// @notice Initializes the contract with the deployer as owner
    constructor() Ownable(msg.sender) {}

    /// @notice Generates a unique key for a lending CLOB based on its parameters
    /// @dev Uses keccak256 hash of concatenated parameters
    /// @param debtToken_ The token that can be borrowed from the CLOB
    /// @param collateralToken_ The token that can be used as collateral
    /// @param maturityMonth_ The month when the CLOB matures (e.g., "MAY")
    /// @param maturityYear_ The year when the CLOB matures
    /// @return The unique key for the lending CLOB
    function _generateLendingCLOBKey(
        address debtToken_,
        address collateralToken_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(debtToken_, collateralToken_, maturityMonth_, maturityYear_));
    }

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
    ) external onlyOwner nonReentrant returns (address) {
        bytes32 key = _generateLendingCLOBKey(debtToken_, collateralToken_, maturityMonth_, maturityYear_);
        if (address(lendingCLOB[key]) != address(0)) revert LendingCLOBAlreadyExists();
        lendingCLOB[key] = new LendingCLOB(msg.sender, debtToken_, collateralToken_, maturityMonth_, maturityYear_);

        emit LendingCLOBCreated(address(lendingCLOB[key]), msg.sender, debtToken_, collateralToken_, maturityMonth_, maturityYear_);

        return address(lendingCLOB[key]);
    }

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
    ) external view returns (address) {
        bytes32 key = _generateLendingCLOBKey(debtToken_, collateralToken_, maturityMonth_, maturityYear_);
        if (address(lendingCLOB[key]) == address(0)) revert LendingCLOBNotFound();
        return address(lendingCLOB[key]);
    }
}