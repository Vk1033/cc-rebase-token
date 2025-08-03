// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author vk1033
 * @notice This is a cross-chain rebase token that incentivizes users to deposit into a vault and gain interest in return.
 */
contract RebaseToken is ERC20 {
    error Rebase__InterestCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18; // Precision factor for interest calculations
    uint256 private s_interestRate = 5e10; // Interest rate for the rebase token
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userlastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {}

    /**
     * @notice Set the interest rate for the rebase token.
     * @param _newInterestRate The new interest rate to be set.
     * @dev This function allows the owner to set a new interest rate, but it can only decrease the current interest rate.
     */
    function setInterestRate(uint256 _newInterestRate) external {
        // Logic to set the new interest rate
        if (_newInterestRate > s_interestRate) {
            revert Rebase__InterestCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;

        emit InterestRateSet(s_interestRate);
    }

    /**
     * @notice Mint new tokens to a specified address.
     * @param _to The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     * @dev This function mints new tokens and updates the user's interest rate and last updated timestamp.
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Get the balance of a user, including accrued interest.
     * @param _user The address of the user to check the balance for.
     * @return The balance of the user, including accrued interest.
     * @dev This function overrides the balanceOf function to include accrued interest since the last update.
     * The interest is calculated based on the time elapsed since the last update and the user's interest rate.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // Calculate the balance considering accrued interest
        return super.balanceOf(_user) + _calculateAccruedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Calculate the accrued interest for a user since their last update.
     * @param _user The address of the user to calculate interest for.
     * @return linearInterest The amount of interest accrued since the last update.
     * @dev This function calculates the interest based on the user's interest rate and the time elapsed since their last update.
     */
    function _calculateAccruedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        uint256 timeElapsed = block.timestamp - s_userlastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    function getUserInterestRate(address user) external view returns (uint256) {
        return s_userInterestRate[user];
    }

    function _mintAccruedInterest(address _user) internal {
        s_userlastUpdatedTimestamp[_user] = block.timestamp;
    }
}
