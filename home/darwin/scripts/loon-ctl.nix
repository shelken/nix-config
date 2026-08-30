{ pkgs, ... }:
{
  script = pkgs.writeShellApplication {
    name = "loon-ctl";
    runtimeInputs = [ pkgs.sqlite ];
    text = ''
      if [[ $# -ne 2 || $1 != "dns" ]]; then
        echo "Usage: loon-ctl dns <domain>" >&2
        exit 2
      fi

      domain=$2
      if [[ ! $domain =~ ^[[:alnum:]_.-]+$ ]]; then
        echo "Invalid domain: $domain" >&2
        exit 2
      fi

      database="/Library/Application Support/com.loon.Loon/record/loon_record.db"
      if [[ ! -r $database ]]; then
        echo "Loon DNS database is not readable: $database" >&2
        exit 1
      fi

      result=$(sqlite3 -readonly -header -box "$database" \
        ".parameter init" \
        ".parameter set @domain '$domain'" \
        "SELECT datetime(queryFinishTime / 1000, 'unixepoch', 'localtime') AS time, domain, ip AS answer, printf('%s:%d', serverIp, serverPort) AS upstream, ttl FROM dnsCaches WHERE domain = @domain COLLATE NOCASE ORDER BY queryFinishTime DESC LIMIT 1;")

      if [[ -z $result ]]; then
        echo "No DNS record found for: $domain" >&2
        exit 1
      fi

      printf '%s\n' "$result"
    '';
  };
}
