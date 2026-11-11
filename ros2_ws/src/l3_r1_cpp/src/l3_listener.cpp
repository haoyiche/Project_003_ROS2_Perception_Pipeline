#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"

int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);

    auto node =
        rclcpp::Node::make_shared("l3_listener");

    auto logger = node->get_logger();

    auto count = std::make_shared<int>(0);

    auto subscription =
        node->create_subscription<std_msgs::msg::String>(
            "/l3/chatter",
            10,
            [logger, count](std_msgs::msg::String::ConstSharedPtr msg) {
                ++(*count);

                if ((*count) % 5 == 0) {
                    RCLCPP_INFO(
                        logger,
                        "Received count: %d, data: '%s'",
                        *count,
                        msg->data.c_str());
                }
            });

    rclcpp::spin(node);

    rclcpp::shutdown();
    return 0;
}