require 'formula'

class CouchdbLucene <Formula
  url 'http://github.com/rnewson/couchdb-lucene/tarball/v0.5.3'
  homepage 'http://github.com/rnewson/couchdb-lucene'
  md5 '1b9be17eb59b6b2839e50eb222bc7e7e'

  depends_on 'couchdb'
  depends_on 'maven'

  def install
    # Skipping tests because the integration test assumes that couchdb-lucene
    # has been integrated with a local couchdb instance. Not sure if there's a
    # way to only disable the integration test.
    system "mvn", "-DskipTests=true"

    system "tar -xzf target/couchdb-lucene-#{version}-dist.tar.gz"
    system "mv couchdb-lucene-#{version}/* #{prefix}"

    (etc + "couchdb/local.d/couchdb-lucene.ini").write ini_file

    launchd_plist "couchdb-lucene" do
      run_at_load true; keep_alive true
      environment_variables "HOME" => "~", "DYLD_LIBRARY_PATH" => "/opt/local/lib:$DYLD_LIBRARY_PATH"
      program_arguments ["#{bin}/run"]
      user_name `whoami`.chomp
      standard_error_path "/dev/null"
      standard_out_path   "/dev/null"
    end
  end

  def caveats; <<-EOS
You can enable couchdb-lucene to automatically load on login with:

  cp "#{prefix}/couchdb-lucene.plist" ~/Library/LaunchAgents/
  launchctl load -w ~/Library/LaunchAgents/couchdb-lucene.plist

Or start it manually with:
  #{bin}/run
EOS
  end

  def ini_file
    return <<-EOS
[couchdb]
os_process_timeout=60000 ; increase the timeout from 5 seconds.

[external]
fti=#{`which python`.chomp} #{prefix}/tools/couchdb-external-hook.py

[httpd_db_handlers]
_fti = {couch_httpd_external, handle_external_req, <<"fti">>}
EOS
  end
end
