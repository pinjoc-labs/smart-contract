// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ILendingCLOBManager} from "./interfaces/ILendingCLOBManager.sol";
import {LendingCLOB} from "./LendingCLOB.sol";

/// @title LendingCLOBManager - Factory contract for creating and managing lending CLOB
/// @notice Manages the creation and retrieval of lending CLOB with different parameters
/// @dev Implements access control and prevents reentrancy attacks
contract LendingCLOBManager is ILendingCLOBManager, Ownable, ReentrancyGuard {
    /// @notice Mapping from CLOB key to LendingCLOB contract
    /// @dev Key is generated from debt token, collateral token, maturity month and year
    mapping(bytes32 => address) public lendingCLOB;

    /// @notice Initializes the contract with the router address
    /// @param router_ The address of the router
    constructor(address router_) Ownable(router_) {}

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
        bytes32 key = _generateLendingCLOBKey(
            debtToken_,
            collateralToken_,
            maturityMonth_,
            maturityYear_
        );
        if (lendingCLOB[key] != address(0)) revert LendingCLOBAlreadyExists();
        lendingCLOB[key] = address(
            new LendingCLOB(
                msg.sender,
                debtToken_,
                collateralToken_,
                maturityMonth_,
                maturityYear_
            )
        );

        emit LendingCLOBCreated(
            lendingCLOB[key],
            msg.sender,
            debtToken_,
            collateralToken_,
            maturityMonth_,
            maturityYear_
        );

        return lendingCLOB[key];
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
        bytes32 key = _generateLendingCLOBKey(
            debtToken_,
            collateralToken_,
            maturityMonth_,
            maturityYear_
        );
        return lendingCLOB[key];
    }
}
