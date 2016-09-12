test_name '(SERVER-1380) Server loads updated CRL after being reloaded'

puppetservice=options['puppetservice']
cert_to_revoke="reload_updated_crl"
server = master.puppet['certname']
host_crl_file = master.puppet['hostcrl']
ca_crl_file = master.puppet['cacrl']
inventory_file = master.puppet['cert_inventory']

teardown do
  step 'Remove revoked CRL cert' do
    on(master, puppet('cert', 'clean', cert_to_revoke),
       {:acceptable_exit_codes => [0, 24]})
  end

  step 'Restore CRL and inventory files' do
    on(master, "if [ -f #{ca_crl_file}.bak ]; " +
        "then mv -f #{ca_crl_file}.bak #{ca_crl_file}; fi")
    on(master, "if [ -f #{host_crl_file}.bak ]; " +
        "then mv -f #{host_crl_file}.bak #{host_crl_file}; fi")
    on(master, "if [ -f #{inventory_file}.bak ]; " +
        "then mv -f #{inventory_file}.bak #{inventory_file}; fi")
  end

  step 'Restart puppetserver service after testing revoked CRL agent' do
    bounce_service(master, puppetservice)
  end
end

step 'Clean up an old cert for the revoked CRL node if there is one' do
  on(master, puppet('cert', 'clean', cert_to_revoke),
     {:acceptable_exit_codes => [0, 24]})
end

step 'Backup CRL and inventory files' do
  on(master, "if [ -f #{ca_crl_file} ]; " +
      "then mv -f #{ca_crl_file} #{ca_crl_file}.bak; fi")
  on(master, "if [ -f #{host_crl_file} ]; " +
      "then mv -f #{host_crl_file} #{host_crl_file}.bak; fi")
  on(master, "if [ -f #{inventory_file} ]; " +
      "then mv -f #{inventory_file} #{inventory_file}.bak; fi")
end


step 'Ask to cleanup the cert a second time, just to recreate the ca_crl file' do
  # Puppet Server chokes if no ca_crl file exists but other SSL files do when
  # it restarts.  This is an ugly way to ensure it gets recreated but it works.
  on(master, puppet('cert', 'clean', cert_to_revoke),
     {:acceptable_exit_codes => [24]})
  on(master, "[ -f #{ca_crl_file} ]")
end

step 'Generate cert to be revoked' do
  on(master, puppet('cert', 'generate', cert_to_revoke))
end

step 'Restart puppetserver service before testing revoked CRL agent' do
  bounce_service(master, puppetservice)
end

step 'Validate that noop agent run successful before cert revoked' do
  on(master, puppet('agent', '--test',
                    '--server', server,
                    '--certname', cert_to_revoke,
                    '--noop'))
end

step 'Revoke cert' do
  on(master, puppet('cert', 'revoke', cert_to_revoke))
end

step 'Validate that noop agent run successful after cert revoked but before reload' do
  on(master, puppet('agent', '--test',
                    '--server', server,
                    '--certname', cert_to_revoke,
                    '--noop'))
end

step 'Reload the server' do
  reload_server
end

step 'Validate that noop run for revoked agent fails with SSL error after server reload' do
  on(master, puppet('agent', '--test',
                    '--server', server,
                    '--certname', cert_to_revoke,
                    '--noop'),
     {:acceptable_exit_codes => [1]}) do |result|
    assert_match(/SSL_connect SYSCALL returned=5/,
                 result.stderr,
                 "Agent run did not fail with SSL error as expected")
  end
end

step 'Validate that noop run for master against itself is still successful after reload' do
  on(master, puppet('agent', '--test',
                    '--server', server,
                    '--certname', server,
                    '--noop'),
     {:acceptable_exit_codes => [0, 2]})
end
