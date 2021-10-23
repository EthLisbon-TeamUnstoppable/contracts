// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IJudgeManager {
    function reportGood(address jugde) external;
    function reportBad(address jugde) external;
}

