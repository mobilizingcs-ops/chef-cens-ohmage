name 'cens-ohmage'
maintainer 'Steve Nolen'
maintainer_email 'technolengy@gmail.com'
license 'Apache 2.0'
description 'Installs/Configures cens-ohmage'
long_description 'Installs/Configures cens-ohmage'
version '0.0.10'

%w(ubuntu).each do |os|
  supports os
end

depends 'nginx', '~>2.7.6'