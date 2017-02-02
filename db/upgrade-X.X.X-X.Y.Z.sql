--
-- PacketFence SQL schema upgrade from X.X.X to X.Y.Z
--

--
-- Table structure for table `ip4log`
--

RENAME TABLE iplog TO ip4log;

ALTER TABLE ip4log
    DROP INDEX iplog_mac_end_time, ADD INDEX ip4log_mac_end_time (mac,end_time),
    DROP INDEX iplog_end_time, ADD INDEX ip4log_end_time (end_time);

--
-- Trigger to insert old record from 'ip4log' in 'ip4log_history' before updating the current one
--

DROP TRIGGER IF EXISTS iplog_insert_in_iplog_history_before_update_trigger;
DELIMITER /
CREATE TRIGGER ip4log_insert_in_ip4log_history_before_update_trigger BEFORE UPDATE ON ip4log
FOR EACH ROW
BEGIN
  INSERT INTO ip4log_history SET ip = OLD.ip, mac = OLD.mac, start_time = OLD.start_time, end_time = CASE
    WHEN OLD.end_time = '0000-00-00 00:00:00' THEN NOW()
    WHEN OLD.end_time > NOW() THEN NOW()
    ELSE OLD.end_time
  END;
END /
DELIMITER ;

--
-- Table structure for table `ip4log_history`
--

RENAME TABLE iplog_history TO ip4log_history;

ALTER TABLE ip4log_history
    DROP INDEX iplog_history_mac_end_time, ADD INDEX ip4log_history_mac_end_time (mac,end_time);

--
-- Table structure for table `ip4log_archive`
--

RENAME TABLE iplog_archive TO ip4log_archive;
