build:
	zola build -o docs
	git restore docs/CNAME

serve:
	zola serve

