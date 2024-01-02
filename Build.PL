use Module::Build;
my $build = Module::Build->new
  (
   dist_name => 'webcheck',
   dist_version_from => 'script/webcheck',
   license  => 'perl',
   requires => {
		'perl'          => '5.10.1',
		'YAML::Tiny'    => '1',
		'Pod::Usage'    => '1',
               },
   test_requires => {
		     'Test::More' => '1',
		    },
   script_files => 'script/webcheck',
  );
$build->create_build_script;
