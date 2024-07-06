
#!/bin/bash
# 交换两个space所有窗口
target_space=$1
target_windows=$(yabai -m query --windows --space $target_space | jq '.[] | .id')
current_space=$(yabai -m query --spaces | jq '.[] | select(."has-focus" == true) | .index')
current_windows=$(yabai -m query --spaces | jq '.[] | select(."has-focus" == true) | .windows | .[]')

if [[ $target_space -eq $current_space ]]; then
  exit 0
fi

for window in $current_windows
do
  echo "switch window $window to space $target_space"
  yabai -m window $window --space $target_space &> /dev/null 
done

for window in $target_windows
do
  echo "switch window $window to space $current_space"
  yabai -m window $window --space $current_space &> /dev/null 
done

# focus to target space 

yabai -m query --spaces --space $target_space | jq -r '.windows[0] // empty' | xargs yabai -m window --focus &> /dev/null

