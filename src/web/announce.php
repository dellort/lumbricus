<?php

# I can only hope that there are no "security issues"
# but anyone could use the server for temporary light-weight storage of data

function exception_handler($exception) {
    # retarded PHP crap doesn't do this automatically
    header("HTTP/1.0 400 Bad Request");
    header("Content-Type: text/plain");
    echo "Error: " , $exception->getMessage(), "\n";
}
set_exception_handler('exception_handler');

# enable output buffer, so headers can be manipulated
# buffer is flushed automatically on script end
ob_start();

$dblink = new PDO('mysql:host=localhost;port=3307;dbname=foo', 'debian-sys-maint', 'xlz5V2owQsZZarzR');

$binary = false;

switch ($_GET["action"]) {
    case "getip":
        # ip is the "detected" remote address
        # remoteip is the actual remote address as seen by the web server
        echo "state=ip\nip=" . get_ip() . "\nremoteip=" . $_SERVER["REMOTE_ADDR"];
        break;
    case "list":
        # return a list of all announcements
        do_timeouts($dblink);
        echo "state=list\n";
        $data = myquery($dblink, "select address, time from server_list");
        foreach ($data as $row) {
            # last | for backwards compatiblity
            echo $row["address"] . "|" . $row["time"] . "|\n";
        }
        break;
    case "blist":
        # return a binary list of all announcements without state prefix
        # format: (4 bytes ip little endian + 2 bytes port little endian)*
        do_timeouts($dblink);
        $data = myquery($dblink, "select address from server_list");
        foreach ($data as $row) {
            # split into ip and port
            $addr = explode(":", $row["address"]);
            echo pack("Vv", ip2long($addr[0]), $addr[1]);
        }
        # for content type
        $binary = true;
        break;
    case "add":
        # add/update an announcement entry
        # not sure how to deal with "address", the internet is full of
        # firewalls and HTTP proxies; how to get the actual address?
        do_timeouts($dblink);
        $address = get_address();
        $dblink->beginTransaction();
        mystatement($dblink, "delete from server_list where address=:addr",
            array(":addr" => $address));
        myquery($dblink, "insert into server_list values(:addr, :time)",
            array(":addr" => $address, ":time" => time()));
        $dblink->commit();
        echo "state=added";
        break;
    case "remove":
        $address = get_address();
        mystatement($dblink, "delete from server_list where address=:addr",
            array(":addr" => $address));
        echo "state=deleted";
        break;
    case "clear":
        # empty caches
        # also used to initially create the database
        # not really a problem to allow this for everyone
        try {
            mystatement($dblink, "drop table server_list");
        } catch (Exception $e) {
            //lol
        }
        mystatement($dblink, "create table server_list (address varchar(100) not null primary key, time integer not null)");
        echo "state=ok";
        break;
    default:
        throw new Exception("invalid action");
}

# when everything went right
if ($binary) {
    header("Content-Type: application/octet-stream");
} else {
    header("Content-Type: text/plain");
}
# seems this doesn't work at all
header('Connection: close');


function do_timeouts($link) {
    $now = time();
    $timeout_sec = 60;
    mystatement($link, "delete from server_list where time < :oldest",
        array(":oldest" => $now - $timeout_sec));
}

function mystatement($link, $blargh, array $params = array()) {
    $sth = myquery($link, $blargh, $params);
    $sth->closeCursor();
}

function myquery($link, $blargh, array $params = array()) {
    $sth = $link->prepare($blargh);
    $res = $sth->execute($params);
    if (!$res) {
        # there's $sth->errorInfo
        function crap($a, $b) {
            return $a . " | " . $b;
        }
        throw new Exception("Database error: " . array_reduce($sth->errorInfo(), "crap"));
    }
    return $sth;
}

function get_ip() {
    # this header should take care of any proxy mess, but actually I don't
    # really know if we need this
    $fwd = $_SERVER["HTTP_X_FORWARDED_FOR"];
    if (isset($fwd)) {
        return $fwd;
    } else {
        return $_SERVER["REMOTE_ADDR"];
    }
}

function get_address() {
    $port = $_GET["port"];
    if (!filter_var($port, FILTER_VALIDATE_INT)) {
        throw new Exception("port argument invalid");
    }
    $port = (int)$port;
    $address = get_ip() . ":" . $port;
    return $address;
}

?>