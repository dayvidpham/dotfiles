find . -name '*.cpp' -exec sed -i 's/\(assignments.*,[[:space:]]\+\)\(70\)}/\1Priority::Low}/' {} \;
