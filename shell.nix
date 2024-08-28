{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    # nativeBuildInputs is usually what you want -- tools you need to run
    nativeBuildInputs = [ 
      pkgs.buildPackages.ruby_3_2
      pkgs.buildPackages.libyaml

      ];
    # buildInputs = [ env nodejs yarn postgresql ];

    shellHook = ''
      export GEM_HOME=$PWD/.nix-gems
      export GEM_PATH=$GEM_HOME
      export PATH=$GEM_HOME/bin:$PATH
      export PATH=$PWD/bin:$PATH

      gem list -i ^bundler$ -v 2.5.18 || gem install bundler --version=2.5.18 --no-document
      bundle config set --local path vendor/bundle

      bundle install
    '';
}
