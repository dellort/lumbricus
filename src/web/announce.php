<?php

# I can only hope that there are no "security issues"
# but anyone could use the server for temporary light-weight storage of data

try {
    $dblink = new PDO('mysql:host=localhost;port=3307;dbname=foo', 'debian-sys-maint', 'xlz5V2owQsZZarzR');

    # output is stored in a variable, because when writing the output directly, the
    # http header can't be changed afterwards (on errors)
    $output = "";

    switch ($_GET["action"]) {
        case "list":
            # return a list of all announcements
            do_timeouts($dblink);
            # xxx sanity check address & info
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
            $address = $_GET["address"];
            $info = $_GET["info"];
            $dblink->beginTransaction();
            mystatement($dblink, "delete from server_list where address=:addr",
                array(":addr" => $address));
            myquery($dblink, "insert into server_list values(:addr, :time, :info)",
                array(":addr" => $address, ":time" => time(), ":info" => $info));
            $dblink->commit();
            $output = "state=added";
            break;
        case "remove":
            $address = $_GET["address"];
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

?>