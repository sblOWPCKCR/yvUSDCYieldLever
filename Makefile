test:
	[ -z $$WEB3_PROVIDER_URI ] && echo set WEB3_PROVIDER_URI env variable || forge test -f $$WEB3_PROVIDER_URI -vvv
