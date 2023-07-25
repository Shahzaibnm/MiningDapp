// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface miningDappV1 {
    function getUserInfo(address user)
        external
        view
        returns (
            uint256 _nodes,
            uint256 _claimedReward,
            uint256 _checkpoint,
            uint256 _referralsReward,
            uint256 _prizePoolIncome,
            uint256 _claimedReferralReward,
            uint256 _claimablePrizePoolIncome,
            uint256 _startTime,
            address _referrer,
            bool _isActive,
            bool _isStaked,
            uint256 _referrals
        );

    function getUserPower(address _user)
        external
        view
        returns (uint256[9] memory _teampower);

    function getUserReferrersPower(address _user)
        external
        view
        returns (uint256[9] memory _teampower);
}

contract miningDapp is Initializable, OwnableUpgradeable {
    bool public launched;
    uint256 public launchTime;
    uint256 public weekTime;
    uint256 public currentWeek;
    uint256 public uniqueStakers;
    uint256 public rewardDistributed;
    uint256 public totalWithdrawanNodes;
    uint256 public currentStakedNodes;

    IERC20MetadataUpgradeable public Fym;
    miningDappV1 public v1;
    uint256 public timeStep;
    uint256 public poolPercent;
    address public miningPool;
    uint256 public minDeposit;
    uint256 public maxDeposit;
    uint256 public percentDivider;
    uint256 public totalComputingPower;
    uint256 public claimDuration;

    uint256[10] bonus;
    uint256[9] uplinebonus;

    function initialize() public initializer {
        OwnableUpgradeable(msg.sender);
        _owner = 0xBA02934d2DD50445Fd08E975eDE02CA6C609d4db;
        Fym = IERC20MetadataUpgradeable(
            0x1b3e2293E64f021a81Fd83c72beAC8169FBd52F9
        );
        v1 = miningDappV1(0xE49001943F404A453F53FBC2365A3179214C2d68);
        // _owner = 0xBA02934d2DD50445Fd08E975eDE02CA6C609d4db;
        launched = true;
        launchTime = 0;
        weekTime = 0;
        currentWeek = 0;
        uniqueStakers = 0;
        rewardDistributed = 0;
        totalWithdrawanNodes = 0;
        currentStakedNodes = 0;
        timeStep = 1 days;
        poolPercent = 30_00;
        miningPool = 0x93d7DD3c5a48f51a769C8Aae33E652a4b1E5Ee58;
        minDeposit = 100 * 10**Fym.decimals();
        maxDeposit = 1500000000 * 10**Fym.decimals();
        percentDivider = 100_00;
        totalComputingPower = 210000;
        claimDuration = 1 days;
    }

    struct User {
        uint256 startTime;
        address referrer;
        uint256 checkpoint;
        uint256 invitedNodes;
        uint256 referralCount;
        uint256 claimedReward;
        uint256 claimablePrizePoolIncome;
        uint256 referralsReward;
        uint256 claimedReferralReward;
        uint256 prizePoolIncome;
        uint256 nodes;
        bool isExists;
        bool isActive;
        bool isStaked;
    }

    struct UserInfo {
        uint256[9] teamPower;
        uint256[9] referrals;
    }

    struct Week {
        address[10] Depositor;
        uint256[10] usersAmount;
    }

    mapping(address => User) internal users;
    mapping(uint256 => Week) internal weeklyData;
    mapping(address => UserInfo) internal UserInfos;

    event STAKE(address Staker, uint256 amount);
    event CLAIM(address Staker, uint256 amount);
    event WITHDRAW(address Staker, uint256 amount);
    event Distribute(address Staker, uint256 amount);

    function launch() external onlyOwner {
        require(!launched, "Already launched");
        launched = true;
        launchTime = block.timestamp;
        weekTime = block.timestamp;
    }

    function calculateWeek() public view returns (uint256) {
        return (block.timestamp - launchTime) / (7 * timeStep);
    }

    function updateWeekly() public {
        if (currentWeek != calculateWeek()) {
            distributePrize();
            currentWeek = calculateWeek();
            weekTime = block.timestamp;
        }
    }

    function stake(address _referrer, uint256 _node) public {
        User storage user = users[msg.sender];
        uint256 amount = _node * 100 * 10**Fym.decimals();
        require(launched, "Wait for launch");
        require(amount >= minDeposit, "Amount less than min amount");
        require(amount <= maxDeposit, "More than max amount");
        updateWeekly();
        if (!user.isExists) {
            user.isExists = true;
            user.startTime = block.timestamp;
            uniqueStakers++;
        }
        user.nodes += _node;
        user.checkpoint = block.timestamp;
        user.isActive = true;
        currentStakedNodes += _node;
        setReferrer(msg.sender, _referrer, _node);
        user.isStaked = true;
        Fym.transferFrom(msg.sender, address(this), amount);
        emit STAKE(msg.sender, amount);
    }

    function setReferrer(
        address _user,
        address _referrer,
        uint256 _amount
    ) internal {
        User storage user = users[_user];
        if (user.referrer != address(0)) {
            users[user.referrer].invitedNodes += _amount;
        }
        if (user.referrer == address(0)) {
            if (
                _referrer != _user &&
                users[_referrer].isStaked &&
                msg.sender != users[_referrer].referrer
            ) {
                user.referrer = _referrer;
                if (_referrer != address(0)) {
                    users[_referrer].invitedNodes += _amount;
                    users[_referrer].referralCount++;
                }
            } else {
                user.referrer = address(0);
            }
        }
        address referrer = user.referrer;
        for (uint256 i = 0; i < 9; i++) {
            if (referrer != address(0)) {
                UserInfos[referrer].referrals[i]++;
                UserInfos[referrer].teamPower[i] += _amount;
                referrer = users[referrer].referrer;
            } else {
                break;
            }
        }

        for (uint256 i; i < weeklyData[currentWeek].Depositor.length; i++) {
            if (weeklyData[currentWeek].Depositor[i] == _referrer) {
                break;
            }
            if (
                users[_referrer].invitedNodes >
                users[weeklyData[currentWeek].Depositor[i]].invitedNodes
            ) {
                address x = _referrer;
                address y;
                for (
                    uint256 j = i;
                    j < weeklyData[currentWeek].Depositor.length;
                    j++
                ) {
                    y = weeklyData[currentWeek].Depositor[j];
                    weeklyData[currentWeek].Depositor[j] = x;
                    x = y;
                    if (y == _referrer) break;
                }
                break;
            }
        }
    }

    function claim() public {
        User storage user = users[msg.sender];
        require(user.isStaked, "User has no stake");
        require(user.isActive, "Already withdrawn");
        require(
            block.timestamp >= claimDuration + user.checkpoint,
            "Wait for atleast 24 hours"
        );
        require(launched, "Wait for launch");
        updateWeekly();
        uint256 rewardAmount;
        rewardAmount = calculateReward(msg.sender, user.checkpoint);
        require(rewardAmount > 0, "Can't claim 0");
        Fym.transferFrom(miningPool, msg.sender, rewardAmount);
        Fym.transferFrom(miningPool, msg.sender, user.referralsReward);
        payable(msg.sender).transfer(user.claimablePrizePoolIncome);
        user.claimedReferralReward += user.referralsReward;
        setRefferalsReward(msg.sender, rewardAmount);
        user.claimedReward += rewardAmount;
        user.prizePoolIncome += user.claimablePrizePoolIncome;
        user.checkpoint = block.timestamp;
        rewardDistributed += rewardAmount;
        user.referralsReward = 0;
        user.claimablePrizePoolIncome = 0;
        emit CLAIM(msg.sender, rewardAmount);
    }

    function setRefferalsReward(address _user, uint256 _amount) private {
        address userReferral = _user;

        for (uint256 i = 1; i <= uplinebonus.length; i++) {
            {
                userReferral = users[userReferral].referrer;
                if (userReferral == address(0)) {
                    break;
                }
                if (users[userReferral].referralCount >= i) {
                    uint256 amount = (_amount * uplinebonus[i - 1]) /
                        percentDivider;

                    users[userReferral].referralsReward += amount;
                }
            }
        }
    }

    function withdraw(uint256 _node) public {
        User storage user = users[msg.sender];
        address referrer = users[msg.sender].referrer;
        require(user.isStaked, "User has no stake");
        require(user.isActive, "Already withdrawn");
        uint256 amount = _node * 100 * 10**Fym.decimals();
        require(launched, "Wait for launch");
        require(
            _node <= user.nodes,
            "nodes Should be less than current staked nodes"
        );

        updateWeekly();
        Fym.transfer(msg.sender, amount);
        user.nodes -= _node;
        currentStakedNodes -= _node;
        totalWithdrawanNodes += _node;
        if (user.nodes == 0) {
            user.isActive = false;
        }

        for (uint256 i = 0; i < 9; i++) {
            if (referrer != address(0)) {
                UserInfos[referrer].teamPower[i] -= _node;
                referrer = users[referrer].referrer;
            } else {
                break;
            }
        }
        if (referrer != address(0)) {
            users[referrer].invitedNodes -= _node;
        }

        emit WITHDRAW(msg.sender, amount);
    }

    function calculateReward(address _user, uint256 _time)
        public
        view
        returns (uint256 _reward)
    {
        User storage user = users[_user];
        uint256 duration = block.timestamp - _time;
        uint256 interval = (duration * 100) / claimDuration;
        uint256 actualComputingPower = currentStakedNodes;
        uint256 pledgeRate = ((totalComputingPower * 100) /
            actualComputingPower);
        uint256 miningOutput = ((Fym.balanceOf(miningPool) * pledgeRate) /
            (actualComputingPower));
        _reward =
            ((miningOutput / actualComputingPower) * (user.nodes * interval)) /
            10000;
    }

    function amountToDistribute() public view returns (uint256) {
        uint256 prizePoolBalance = address(this).balance;
        uint256 _prize = (prizePoolBalance * poolPercent) / percentDivider;
        return _prize;
    }

    function distributePrize() private {
        uint256 _amount = amountToDistribute();
        for (uint256 i = 0; i < weeklyData[currentWeek].Depositor.length; i++) {
            if (weeklyData[currentWeek].Depositor[i] == address(0)) {
                break;
            }
            uint256 amount = (_amount * bonus[i]) / percentDivider;
            weeklyData[currentWeek].usersAmount[i] = amount;
            users[weeklyData[currentWeek].Depositor[i]]
                .claimablePrizePoolIncome += amount;
            emit Distribute(weeklyData[currentWeek].Depositor[i], amount);
        }
    }

    function getWeekData(uint256 _index)
        public
        view
        returns (address[10] memory _users, uint256[10] memory _amounts)
    {
        _users = weeklyData[_index].Depositor;
        _amounts = weeklyData[_index].usersAmount;
    }

    function withdrawStuckToken(address _token, uint256 _amount)
        public
        onlyOwner
    {
        IERC20MetadataUpgradeable(_token).transfer(msg.sender, _amount);
    }

    function setTime(uint256 _step, uint256 _claimDuration) external onlyOwner {
        timeStep = _step;
        claimDuration = _claimDuration;
    }

    function changeToken(address _token) public onlyOwner {
        Fym = IERC20MetadataUpgradeable(_token);
    }

    function setDepositLimits(uint256 _minDeposit, uint256 _maxDeposit)
        public
        onlyOwner
    {
        minDeposit = _minDeposit;
        maxDeposit = _maxDeposit;
    }

    function migrateContract(address _user) internal {
        (
            users[_user].nodes,
            users[_user].claimedReward,
            users[_user].checkpoint,
            users[_user].referralsReward,
            users[_user].prizePoolIncome,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = v1.getUserInfo(_user);
    }

    function migrateContract1(address _user) internal {
        (
            ,
            ,
            ,
            ,
            ,
            users[_user].claimedReferralReward,
            users[_user].claimablePrizePoolIncome,
            users[_user].startTime,
            users[_user].referrer,
            ,
            ,

        ) = v1.getUserInfo(_user);
    }

    function migrateContract2(address _user) internal {
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            users[_user].isActive,
            users[_user].isStaked,
            users[_user].referralCount
        ) = v1.getUserInfo(_user);
    }

    function migrateData(address _user) public onlyOwner {
        migrateContract(_user);
        migrateContract1(_user);
        migrateContract2(_user);
        getUserslevels(_user);
    }

    function setdata1(
        address _user,
        uint256 _nodes,
        uint256 _claimedReward,
        uint256 _checkpoint,
        uint256 _referralsReward,
        uint256 _prizePoolIncome,
        uint256 _claimedReferralReward
    ) public onlyOwner {
        users[_user].nodes = _nodes;
        users[_user].claimedReward = _claimedReward;
        users[_user].checkpoint = _checkpoint;
        users[_user].referralsReward = _referralsReward;
        users[_user].prizePoolIncome = _prizePoolIncome;
        users[_user].claimedReferralReward = _claimedReferralReward;
    }

    function setdata2(
        address _user,
        uint256 _claimablePrizePoolIncome,
        uint256 _startTime,
        address _referrer,
        bool _isActive,
        bool _isStaked,
        uint256 _referralCount, uint256[9] memory arr0,uint256[9] memory arr1
    ) public onlyOwner {
        users[_user].claimablePrizePoolIncome = _claimablePrizePoolIncome;
        users[_user].startTime = _startTime;
        users[_user].referrer = _referrer;
        users[_user].isActive = _isActive;
        users[_user].isStaked = _isStaked;
        users[_user].referralCount = _referralCount;
        UserInfos[_user].teamPower = arr0;
        UserInfos[_user].referrals = arr1;
    }

    function getUserslevels(address _user) internal {
        UserInfos[_user].teamPower = v1.getUserPower(_user);
        UserInfos[_user].referrals = v1.getUserReferrersPower(_user);
    }

    function setVariables(
        uint256 _cuurentStakedNodes,
        uint256 _currentWeek,
        uint256 _launchTime,
        bool _launced,
        uint256 _rewardDistributed,
        uint256 _totalWithdrawanNodes,
        uint256 _uniqueStakers,
        uint256 _weekTime
    ) public onlyOwner {
        currentStakedNodes = _cuurentStakedNodes;
        currentWeek = _currentWeek;
        launchTime = _launchTime;
        launched = _launced;
        rewardDistributed = _rewardDistributed;
        totalWithdrawanNodes = _totalWithdrawanNodes;
        uniqueStakers = _uniqueStakers;
        weekTime = _weekTime;
    }

    function getUserPower(address _user)
        public
        view
        returns (uint256[9] memory _teampower)
    {
        for (uint256 i = 0; i < 9; i++) {
            _teampower[i] = UserInfos[_user].teamPower[i];
        }
        return _teampower;
    }

    function getUserReferrersPower(address _user)
        public
        view
        returns (uint256[9] memory _teampower)
    {
        for (uint256 i = 0; i < 9; i++) {
            _teampower[i] = UserInfos[_user].referrals[i];
        }
        return _teampower;
    }

    function getCurrentYield(address _user) public view returns (uint256 _apy) {
        User storage user = users[_user];
        uint256 time = block.timestamp - claimDuration;
        uint256 perDay = calculateReward(_user, time);
        _apy = ((perDay * 365) / user.nodes) * 100;
    }

    function changeMiningPool(address _miningPool) public onlyOwner {
        miningPool = _miningPool;
    }

    function withdrawStuckBNBAmount(uint256 _amount) public onlyOwner {
        payable(msg.sender).transfer(_amount);
    }

    function getUserInfo(address _user)
        public
        view
        returns (
            uint256 _nodes,
            uint256 _claimedReward,
            uint256 _checkpoint,
            uint256 _referralsReward,
            uint256 _prizePoolIncome,
            uint256 _claimedReferralReward,
            uint256 _claimablePrizePoolIncome,
            uint256 _startTime,
            address _referrer,
            bool _isActive,
            bool _isStaked,
            uint256[2] memory _arr
        )
    {
        User storage user = users[_user];
        _nodes = user.nodes;
        _claimedReward = user.claimedReward;
        _checkpoint = user.checkpoint;
        _startTime = user.startTime;
        _referrer = user.referrer;
        _isActive = user.isActive;
        _prizePoolIncome = user.prizePoolIncome;
        _isStaked = user.isStaked;
        _arr[0] = user.invitedNodes;
        _arr[1] = user.referralCount;
        _referralsReward = user.referralsReward;
        _claimedReferralReward = user.claimedReferralReward;
        _claimablePrizePoolIncome = user.claimablePrizePoolIncome;
    }

    receive() external payable {}
}
