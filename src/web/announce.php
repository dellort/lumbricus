<?php

# I can only hope that there are no "security issues"
# but anyone could use the server for temporary light-weight storage of data

try {
    $dblink = new PDO('mysql:host=localhost;port=3307;dbname=foo', 'debian-sys-maint', 'xlz5V2owQsZZarzR');

    # output is stored in a variable, because when writing the output directly, the
    # http header can't be changed afterwards (on errors)
    $output = "";

    switch ($_GET["action"]) {
        case "getip":
            # ip is the "detected" remote address
            # remoteip is the actual remote address as seen by the web server
            $output = "state=ip\nip=" . get_ip() . "\nremoteip=" . $_SERVER["REMOTE_ADDR"];
            break;
        case "list":
            # return a list of all announcements
            do_timeouts($dblink);
            $output = "state=list\n";
            $data = myquery($dblink, "select address, time, info from server_list");
            foreach ($data as $row) {
                $output = $output . $row["address"] . "|" . $row["time"]
                    . "|" . $row["info"] . "\n";
            }
            break;
        case "add":
            # add/update an announcement entry
            # not sure how to deal with "address", the internet is full of
            # firewalls and HTTP proxies; how to get the actual address?
            do_timeouts($dblink);
            $address = get_address();
            $info = $_GET["info"];
            $info_ok = false;
            if (filter_var($info, FILTER_SANITIZE_STRING)) {
                # sorry I have no clue
                # it doesn't even work lololoo
                $info_ok = true;
                for ($n = 0; $n < strlen($info); $n = $n + 1) {
                    if (($info[$n] < 32) || ($info[$n] > 127)) {
                        $info_ok = false;
                        break;
                    }
                }
            }
            if (!info_ok) {
                throw new Exception("info argument invalid");
            }
            $dblink->beginTransaction();
            mystatement($dblink, "delete from server_list where address=:addr",
                array(":addr" => $address));
            myquery($dblink, "insert into server_list values(:addr, :time, :info)",
                array(":addr" => $address, ":time" => time(), ":info" => $info));
            $dblink->commit();
            $output = "state=added";
            break;
        case "remove":
            $address = get_address();
            mystatement($dblink, "delete from server_list where address=:addr",
                array(":addr" => $address));
            $output = "state=deleted";
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
            mystatement($dblink, "create table server_list (address varchar(100) not null primary key, time integer not null, info varchar(100) not null)");
            $output = "state=ok";
            break;
        default:
            throw new Exception("invalid action");
    }

    # when everything went right
    header("Content-Type: text/plain");
    header("Connection: Close"); #how to do this correctly?
    echo $output;

} catch (Exception $e) {
    # retarded PHP crap doesn't do this automatically
    header("HTTP/1.0 400 Bad Request");
    throw $e;
}

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