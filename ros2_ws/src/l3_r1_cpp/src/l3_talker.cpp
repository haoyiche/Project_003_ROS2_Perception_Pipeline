#include <chrono>
#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"

int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);

    auto node =
        rclcpp::Node::make_shared("l3_talker");

    auto publisher =
        node->create_publisher<std_msgs::msg::String>(
            "/l3/chatter", 10);

    auto timer = node->create_wall_timer(
        std::chrono::milliseconds(200),
        [publisher]() {
            std_msgs::msg::String msg;
            msg.data = "RGBD ready";
            publisher->publish(msg);
        });

    rclcpp::spin(node);

    rclcpp::shutdown();
    return 0;
}