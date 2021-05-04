# README

this project is just to practice deploying rails API application

## Environment

- ruby: 3.0.0

- rails: 6.1.x

- db: postgresql

- server system: Ubuntu 20.04

- ruby manage: rbenv

- deployment: capistrano + puma + nginx


### reference

- [coderwall](https://coderwall.com/p/ttrhow/deploying-rails-app-using-nginx-puma-and-capistrano-3)

- [Maththew Hoelter](https://matthewhoelter.com/2020/11/10/deploying-ruby-on-rails-for-ubuntu-2004.html)

### Basic Doc

- [capistrano](https://github.com/capistrano/capistrano)

- [capistrano-puma](https://github.com/seuros/capistrano-puma)


## Step

### 1. setting server

create user for deployer with sudo grant

```bash
$ ssh root@server
$ adduser/userdel deployer  # create/remove user for deployment
$ usermod -aG sudo deployer # move user to sudo group or change grant menully by vi /etc/sudoers
$ su deployer
```

#### install basic software

```bash
$ sudo apt-get update -y  # update software source
$ sudo apt-get install build-essential git libssl-dev   # install basic lib-dev
```

#### install basic node
```bash
$ sudo apt-get install node # install node
```

#### install ruby by rbenv

```bash
$ sudo apt install rbenv
$ rbenv init
$ cd ~/.rbenv && mkdir plugins
$ git clone https://github.com/rbenv/ruby-build.git
$ git clone https://github.com/rbenv/ruby-vars.git
$ git clone https://github.com/andorchen/rbenv-china-mirror.git "$(rbenv root)"/plugins/rbenv-china-mirror
$ rbenv install 3.0.0
$ rbenv rehash
$ gem install bundle
$ gem install rails
```

#### install postgresql 

```bash
$ sudo apt-get install postgresql postgresql-contrib libpg-dev # must install libpg-dev otherwise cause gem install pg failed
$ service postgresql start/restart
$ sudo -u postgres createuser --superuser deployer
$ createdb -O deployer dbname
$ psql dbname
/password
```

#### install nginx 

```bash
$ sudo apt-get install nginx
$ service nginx start/restart
```

### 2. Capistrano + puma

Gemfile:

```ruby
gem 'listen', '~> 3.3'

group :development do
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem "capistrano", require: false
  gem "capistrano-rbenv", require: false
  gem "capistrano-rails", require: false
  gem 'capistrano3-puma', require: false
  gem 'capistrano-bundler', require: false
  gem 'sshkit-sudo', require: false
end
```

```bash
$ cap install
```

Capfile:
```ruby
require 'sshkit/sudo'
require "capistrano/rbenv"
require "capistrano/bundler"
require "capistrano/rails/migrations"
require 'capistrano/puma'
install_plugin Capistrano::Puma  # Default puma tasks
install_plugin Capistrano::Puma::Workers  # if you want to control the workers (in cluster mode)
install_plugin Capistrano::Puma::Jungle # if you need the jungle tasks
install_plugin Capistrano::Puma::Monit  # if you need the monit tasks
install_plugin Capistrano::Puma::Nginx
# install_plugin Capistrano::Puma::Daemon
install_plugin Capistrano::Puma::Systemd
```

config/deploy.rb
```ruby
server ENV["APP_SERVER"], roles: [:web, :app, :db], primary: true

set :application, "rails-api-deploy-test"
set :repo_url, "git@github.com:july-12/rails-api-deploy-test.git"
set :user, ENV['APP_SERVER_USER']

set :bundle_config, { deployment: false } 

set :pty,             true
set :use_sudo,        false
set :stage,           :production
set :deploy_via,      :remote_cache
set :deploy_to,       "/home/#{fetch(:user)}/apps/#{fetch(:application)}"
set :ssh_options,     { forward_agent: true, user: fetch(:user), keys: %w(~/.ssh/id_rsa.pub) }

set :puma_threads,    [4, 16]
set :puma_workers,    0
set :rbenv_custom_path, "/home/#{fetch(:user)}/.rbenv"
# append :rbenv_map_bins, 'puma', 'pumactl'

set :puma_bind,       "unix://#{shared_path}/tmp/sockets/#{fetch(:application)}-puma.sock"

namespace :puma do
  desc 'Create Directories for Puma Pids and Socket'
  task :make_dirs do
    on roles(:app) do
      execute "mkdir #{shared_path}/tmp/sockets -p"
      execute "mkdir #{shared_path}/tmp/pids -p"
    end
  end

  before :start, :make_dirs
end

namespace :deploy do
  desc "Make sure local git is in sync with remote."
  task :check_revision do
    on roles(:app) do
      unless `git rev-parse HEAD` == `git rev-parse origin/master`
        puts "WARNING: HEAD is not the same as origin/master"
        puts "Run `git push` to sync changes."
        exit
      end
    end
  end

  desc 'Initial Deploy'
  task :initial do
    on roles(:app) do
      before 'deploy:restart', 'puma:start'
      invoke 'deploy'
    end
  end

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      invoke 'puma:restart'
    end
  end

  before :starting,     :check_revision
  # after  :finishing,    :compile_assets
  after  :finishing,    :cleanup
  after  :finishing,    :restart
end

append :linked_files, "config/database.yml", ".rbenv-vars"
append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system"
```

### QA

you might still encounter some problem even throught you follow above steps very closely, so I will list some QA to help resolve the issue I met.

1. Q: hanging out ask sudo password when cap production deploy:initial

   A: use gem [sshkit-sudo](https://github.com/kentaroi/sshkit-sudo) to handle

2. Q: bundle platforms [] but your local are "x86_64-darwin-19"

   A: remove deployment setting by: set :bundle_config, { deployment: false }  // config/deploy.rb

3. Q: no task: rake assets:precomplile 
  
   A: remove task: **require "capistrano/rails/assets"** in Capfile

4. Q: can't start puma monit

   A: need to install monit firstly

   ```bash
   $ sudo apt-get install monit
   $ sudo service monit start / status
   ```
5. Q: Monit daemon - error connecting to the monit daemon

   A: reference to [this](https://stackoverflow.com/questions/28187786/monit-daemon-error-connecting-to-the-monit-daemon)
   ```ruby
    # sudo vi /etc/monit/monitrc
    set httpd port 2812
        use address localhost  # only accept connection from localhost
        allow localhost        # allow localhost to connect to the server and
        allow admin:monit
   ```
6. Q: puma.service start fail

   A: maybe content setting wrong: __ExecStart=$HOME/.rbenv/bin/rbenv exec bundle exec puma -C__. so need to point out rbenv path specificly.

   ```ruby
   # in config/deploy.rb
    set :rbenv_custom_path, "/home/#{fetch(:user)}/.rbenv"
   ```

7. Q: nothing return after deploy finish

   A: maybe puma not start successfully, need to take **systemctl status puma.service** to check log. And also cause as can't open puma.access.log / puma.error.log file permission error. so need to change owner for those files by: sudo chown deployer puma.*.log. It's better setting these files to link_dir.
   
#### update 2021-05-04 部署OLE项目碰到的问题及修复方法

1.  puma 服务启动失败问题: 

     ole_backend.service 的User未设置: deployer
     
2.  部署https服务的配置
     
     https://gist.github.com/july-12/d6c27d718f0954d5c85b28f69fc573c0
     
3.  部署到生产环境, JWT的校验失败问题
      - lib/json_web_token中的scret_base_key未正确统一设置: ENV[‘SCRET_BASE_KEY']
      - [code](https://github.com/hggeorgiev/rails-jwt-auth-tutorial)
